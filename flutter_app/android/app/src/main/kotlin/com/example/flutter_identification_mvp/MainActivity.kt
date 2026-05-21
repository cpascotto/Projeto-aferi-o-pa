package com.example.flutter_identification_mvp

import android.Manifest
import android.annotation.SuppressLint
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothDevice
import android.bluetooth.BluetoothGatt
import android.bluetooth.BluetoothGattCallback
import android.bluetooth.BluetoothGattCharacteristic
import android.bluetooth.BluetoothGattDescriptor
import android.bluetooth.BluetoothManager
import android.bluetooth.BluetoothProfile
import android.bluetooth.le.ScanCallback
import android.bluetooth.le.ScanResult
import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.util.Log
import android.view.WindowManager
import com.chaquo.python.PyException
import com.chaquo.python.Python
import com.chaquo.python.android.AndroidPlatform
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.util.Base64
import java.util.UUID
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.CountDownLatch
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean

class MainActivity : FlutterActivity() {
    companion object {
        private const val deepFaceTag = "DeepFaceChannel"
        private const val bloodPressureTag = "BloodPressureBle"
        private const val deepFaceChannelName = "afericao_automatizada_mobile/deepface"
        private const val bloodPressureChannelName =
            "afericao_automatizada_mobile/blood_pressure_ble"
        private const val totemModeChannelName = "afericao_automatizada_mobile/totem_mode"
        private const val defaultModelName = "Facenet512"
        private const val bloodPressurePermissionRequest = 7304

        private const val defaultTargetDeviceName = "BT-BPM BLE"
        private val serviceFff0: UUID = UUID.fromString("0000fff0-0000-1000-8000-00805f9b34fb")
        private val charFff4: UUID = UUID.fromString("0000fff4-0000-1000-8000-00805f9b34fb")
        private val charFff5: UUID = UUID.fromString("0000fff5-0000-1000-8000-00805f9b34fb")
        private val clientConfig: UUID = UUID.fromString("00002902-0000-1000-8000-00805f9b34fb")
        private val syncCommand: ByteArray = byteArrayOf(0x6C, 0x37, 0x01, 0x00, 0x5A)
    }

    private var currentTargetDeviceName = ""
    private var currentTargetDeviceAddress = ""

    private val mainHandler = Handler(Looper.getMainLooper())
    private val embeddingExecutor: ExecutorService = Executors.newSingleThreadExecutor()
    private val bloodPressureExecutor: ExecutorService = Executors.newSingleThreadExecutor()
    private val bloodPressureCancelled = AtomicBoolean(false)
    private var pendingBloodPressureResult: MethodChannel.Result? = null
    private var pendingBluetoothPermissionResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        if (!Python.isStarted()) {
            Python.start(AndroidPlatform(applicationContext))
        }

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            deepFaceChannelName,
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "warmup" -> {
                    val modelName = call.argument<String>("modelName") ?: defaultModelName

                    embeddingExecutor.execute {
                        try {
                            Log.i(
                                deepFaceTag,
                                "Aquecendo runtime Python/DeepFace com modelo $modelName.",
                            )
                            warmupDeepFace(modelName)
                            Log.i(deepFaceTag, "Warmup Python/DeepFace concluido.")
                            mainHandler.post {
                                result.success(true)
                            }
                        } catch (error: PyException) {
                            Log.e(deepFaceTag, "Falha do Python/DeepFace no warmup.", error)
                            mainHandler.post {
                                result.error(
                                    "deepface_warmup_python_error",
                                    error.message ?: "Falha Python ao aquecer DeepFace.",
                                    error.stackTraceToString(),
                                )
                            }
                        } catch (error: Throwable) {
                            Log.e(deepFaceTag, "Falha nativa no warmup DeepFace.", error)
                            mainHandler.post {
                                result.error(
                                    "deepface_warmup_native_error",
                                    error.message ?: "Falha nativa ao aquecer DeepFace.",
                                    error.stackTraceToString(),
                                )
                            }
                        }
                    }
                }

                "extractEmbedding" -> {
                    val imageBytes = call.argument<ByteArray>("imageBytes")
                    val modelName = call.argument<String>("modelName") ?: defaultModelName

                    val hasEncodedInput = imageBytes != null && imageBytes.isNotEmpty()

                    if (!hasEncodedInput) {
                        result.error(
                            "invalid_args",
                            "imageBytes e obrigatorio.",
                            null,
                        )
                        return@setMethodCallHandler
                    }

                    embeddingExecutor.execute {
                        try {
                            Log.i(
                                deepFaceTag,
                                "Iniciando geracao local de embedding DeepFace com modelo $modelName.",
                            )
                            val embedding = extractEmbeddingWithDeepFace(
                                imageBytes = imageBytes!!,
                                modelName = modelName,
                            )
                            mainHandler.post {
                                result.success(embedding)
                            }
                        } catch (error: PyException) {
                            Log.e(deepFaceTag, "Falha do Python/DeepFace ao gerar embedding.", error)
                            mainHandler.post {
                                result.error(
                                    "deepface_python_error",
                                    error.message ?: "Falha Python ao gerar embedding DeepFace.",
                                    error.stackTraceToString(),
                                )
                            }
                        } catch (error: Throwable) {
                            Log.e(deepFaceTag, "Falha ao gerar embedding DeepFace.", error)
                            mainHandler.post {
                                result.error(
                                    "deepface_native_error",
                                    error.message ?: "Falha nativa ao gerar embedding DeepFace.",
                                    error.stackTraceToString(),
                                )
                            }
                        }
                    }
                }

                else -> result.notImplemented()
            }
        }

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            bloodPressureChannelName,
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "captureMeasurement" -> startBloodPressureCapture(result)
                "stopCapture" -> {
                    bloodPressureCancelled.set(true)
                    result.success(true)
                }
                "isBluetoothEnabled" -> {
                    val btManager =
                        getSystemService(Context.BLUETOOTH_SERVICE) as BluetoothManager
                    result.success(btManager.adapter?.isEnabled == true)
                }
                "requestEnableBluetooth" -> {
                    val enableIntent =
                        android.content.Intent(BluetoothAdapter.ACTION_REQUEST_ENABLE)
                    startActivity(enableIntent)
                    result.success(true)
                }
                "ensureBluetoothPermissions" -> {
                    ensureBluetoothPermissions(result)
                }
                "setTargetDevice" -> {
                    val name = call.argument<String>("name") ?: ""
                    val id = call.argument<String>("id") ?: ""
                    currentTargetDeviceName = name
                    currentTargetDeviceAddress = id.uppercase()
                    Log.i(
                        bloodPressureTag,
                        "Medidor BLE alvo: ${currentTargetDeviceName.ifBlank { "sem nome" }} / ${currentTargetDeviceAddress.ifBlank { "sem id" }}",
                    )
                    result.success(true)
                }
                "setTargetDeviceName" -> {
                    val name = call.argument<String>("name") ?: ""
                    currentTargetDeviceName = name.ifBlank { defaultTargetDeviceName }
                    currentTargetDeviceAddress = ""
                    Log.i(bloodPressureTag, "Dispositivo alvo legado: $currentTargetDeviceName")
                    result.success(true)
                }
                "getBondedDevices" -> {
                    val btManager =
                        getSystemService(Context.BLUETOOTH_SERVICE) as BluetoothManager
                    val adapter = btManager.adapter
                    if (adapter == null || !adapter.isEnabled) {
                        result.success(emptyList<Map<String, String>>())
                        return@setMethodCallHandler
                    }
                    @SuppressLint("MissingPermission")
                    val bonded = adapter.bondedDevices
                        ?.mapNotNull { device ->
                            val name = device.name?.takeIf { it.isNotBlank() }
                                ?: return@mapNotNull null
                            mapOf(
                                "name" to name,
                                "id" to device.address,
                                "address" to device.address,
                            )
                        } ?: emptyList()
                    result.success(bonded)
                }
                "scanBluetoothDevices" -> {
                    val btManager =
                        getSystemService(Context.BLUETOOTH_SERVICE) as BluetoothManager
                    val adapter = btManager.adapter
                    if (adapter == null || !adapter.isEnabled) {
                        result.success(emptyList<Map<String, String>>())
                        return@setMethodCallHandler
                    }
                    val scanner = adapter.bluetoothLeScanner
                    if (scanner == null) {
                        result.success(emptyList<Map<String, String>>())
                        return@setMethodCallHandler
                    }

                    // Inclui dispositivos já pareados para aparecerem imediatamente.
                    @SuppressLint("MissingPermission")
                    val bonded = adapter.bondedDevices
                        ?.mapNotNull { device ->
                            val name = device.name?.takeIf { it.isNotBlank() }
                                ?: return@mapNotNull null
                            mapOf(
                                "name" to name,
                                "id" to device.address,
                                "address" to device.address,
                            )
                        } ?: emptyList()

                    val found = mutableListOf<Map<String, Any>>()
                    val seen = mutableSetOf<String>()

                    bonded.forEach { d ->
                        val address = d["address"] ?: return@forEach
                        if (seen.add(address)) found.add(d)
                    }

                    val scanCb = object : ScanCallback() {
                        override fun onScanResult(
                            callbackType: Int,
                            scanResult: ScanResult,
                        ) {
                            val name =
                                scanResult.scanRecord?.deviceName
                                    ?: scanResult.device.name
                                    ?: return
                            if (name.isBlank()) return
                            val address = scanResult.device.address
                            if (seen.add(address)) {
                                found.add(
                                    mapOf(
                                        "name" to name,
                                        "id" to address,
                                        "address" to address,
                                        "rssi" to scanResult.rssi,
                                    ),
                                )
                            }
                        }

                        override fun onBatchScanResults(
                            results: MutableList<ScanResult>,
                        ) {
                            results.forEach { onScanResult(0, it) }
                        }
                    }

                    val scanSettings =
                        android.bluetooth.le.ScanSettings.Builder()
                            .setScanMode(
                                android.bluetooth.le.ScanSettings.SCAN_MODE_LOW_LATENCY,
                            )
                            .build()

                    bloodPressureExecutor.execute {
                        scanner.startScan(null, scanSettings, scanCb)
                        Thread.sleep(5_000)
                        scanner.stopScan(scanCb)
                        mainHandler.post { result.success(found) }
                    }
                }
                else -> result.notImplemented()
            }
        }

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            totemModeChannelName,
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "setKeepScreenOn" -> {
                    val enabled = call.argument<Boolean>("enabled") ?: true
                    if (enabled) {
                        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                    } else {
                        window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                    }
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)

        if (requestCode != bloodPressurePermissionRequest) return

        val captureResult = pendingBloodPressureResult
        if (captureResult != null) {
            pendingBloodPressureResult = null
            if (grantResults.all { it == PackageManager.PERMISSION_GRANTED }) {
                startBloodPressureCapture(captureResult)
            } else {
                captureResult.error(
                    "bluetooth_permission_denied",
                    "Permissao de Bluetooth negada.",
                    null,
                )
            }
            return
        }

        val permissionResult = pendingBluetoothPermissionResult ?: return
        pendingBluetoothPermissionResult = null
        if (grantResults.all { it == PackageManager.PERMISSION_GRANTED }) {
            permissionResult.success(true)
        } else {
            permissionResult.error(
                "bluetooth_permission_denied",
                "Permissao de Bluetooth negada.",
                null,
            )
        }
    }

    override fun onDestroy() {
        bloodPressureCancelled.set(true)
        embeddingExecutor.shutdownNow()
        bloodPressureExecutor.shutdownNow()
        super.onDestroy()
    }

    private fun extractEmbeddingWithDeepFace(
        imageBytes: ByteArray,
        modelName: String,
    ): List<Double> {
        val python = Python.getInstance()
        val module = python.getModule("deepface_bridge")
        val base64Image = Base64.getEncoder().encodeToString(imageBytes)
        val response = module.callAttr("extract_embedding", base64Image, modelName)
        return response.asList().map { item -> item.toDouble() }
    }

    private fun warmupDeepFace(modelName: String) {
        val python = Python.getInstance()
        val module = python.getModule("deepface_bridge")
        module.callAttr("warmup_model", modelName)
    }

    private fun startBloodPressureCapture(result: MethodChannel.Result) {
        val missingPermissions = missingBloodPressurePermissions()
        if (missingPermissions.isNotEmpty()) {
            if (pendingBloodPressureResult != null) {
                result.error(
                    "bluetooth_capture_running",
                    "Ja existe uma captura Bluetooth em andamento.",
                    null,
                )
                return
            }
            pendingBloodPressureResult = result
            requestPermissions(
                missingPermissions.toTypedArray(),
                bloodPressurePermissionRequest,
            )
            return
        }

        bloodPressureCancelled.set(false)
        bloodPressureExecutor.execute {
            try {
                val measurement = captureBloodPressureMeasurement()
                mainHandler.post {
                    result.success(measurement)
                }
            } catch (error: Throwable) {
                Log.e(bloodPressureTag, "Falha na captura BLE.", error)
                mainHandler.post {
                    result.error(
                        "blood_pressure_ble_error",
                        error.message ?: "Falha ao capturar afericao por Bluetooth.",
                        error.stackTraceToString(),
                    )
                }
            }
        }
    }

    private fun ensureBluetoothPermissions(result: MethodChannel.Result) {
        val missingPermissions = missingBloodPressurePermissions()
        if (missingPermissions.isEmpty()) {
            result.success(true)
            return
        }

        if (pendingBluetoothPermissionResult != null || pendingBloodPressureResult != null) {
            result.error(
                "bluetooth_permission_pending",
                "Ja existe uma solicitacao de permissao Bluetooth em andamento.",
                null,
            )
            return
        }

        pendingBluetoothPermissionResult = result
        requestPermissions(
            missingPermissions.toTypedArray(),
            bloodPressurePermissionRequest,
        )
    }

    private fun missingBloodPressurePermissions(): List<String> {
        val permissions = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            listOf(
                Manifest.permission.BLUETOOTH_SCAN,
                Manifest.permission.BLUETOOTH_CONNECT,
            )
        } else {
            listOf(Manifest.permission.ACCESS_FINE_LOCATION)
        }

        return permissions.filter {
            checkSelfPermission(it) != PackageManager.PERMISSION_GRANTED
        }
    }

    @SuppressLint("MissingPermission")
    private fun captureBloodPressureMeasurement(): Map<String, Any> {
        val bluetoothManager =
            getSystemService(Context.BLUETOOTH_SERVICE) as BluetoothManager
        val adapter = bluetoothManager.adapter
            ?: throw IllegalStateException("Bluetooth indisponivel neste aparelho.")

        if (!adapter.isEnabled) {
            throw IllegalStateException("Bluetooth desligado.")
        }
        if (currentTargetDeviceAddress.isBlank()) {
            throw IllegalStateException(
                "Medidor Bluetooth nao configurado. Selecione o dispositivo na tela de administrador.",
            )
        }

        while (!bloodPressureCancelled.get()) {
            Log.i(
                bloodPressureTag,
                "Procurando medidor ${currentTargetDeviceName.ifBlank { "sem nome" }} ($currentTargetDeviceAddress).",
            )
            val device = scanForBloodPressureDevice(adapter)
            if (device == null) {
                Thread.sleep(2_000)
                continue
            }

            Log.i(bloodPressureTag, "Conectando em ${device.address}.")
            val measurement = connectAndSyncBloodPressure(device)
            if (measurement != null) {
                return measurement
            }

            Thread.sleep(2_000)
        }

        throw IllegalStateException("Captura Bluetooth cancelada.")
    }

    @SuppressLint("MissingPermission")
    private fun scanForBloodPressureDevice(adapter: BluetoothAdapter): BluetoothDevice? {
        val scanner = adapter.bluetoothLeScanner
            ?: throw IllegalStateException("Scanner BLE indisponivel.")

        val latch = CountDownLatch(1)
        var foundDevice: BluetoothDevice? = null
        val callback = object : ScanCallback() {
            override fun onScanResult(callbackType: Int, result: ScanResult) {
                val deviceAddress = result.device.address.uppercase()
                if (deviceAddress == currentTargetDeviceAddress) {
                    foundDevice = result.device
                    latch.countDown()
                }
            }

            override fun onBatchScanResults(results: MutableList<ScanResult>) {
                for (result in results) {
                    onScanResult(0, result)
                }
            }

            override fun onScanFailed(errorCode: Int) {
                Log.e(bloodPressureTag, "Falha no scan BLE: $errorCode.")
                latch.countDown()
            }
        }

        scanner.startScan(callback)
        latch.await(6, TimeUnit.SECONDS)
        scanner.stopScan(callback)
        return foundDevice
    }

    @SuppressLint("MissingPermission")
    private fun connectAndSyncBloodPressure(device: BluetoothDevice): Map<String, Any>? {
        val records = ConcurrentHashMap<Int, ByteArray>()
        val done = CountDownLatch(1)
        val servicesReady = CountDownLatch(1)
        val disconnected = AtomicBoolean(false)
        var expectedTotal: Int? = null
        var gattRef: BluetoothGatt? = null
        var setupError: Throwable? = null

        val callback = object : BluetoothGattCallback() {
            override fun onConnectionStateChange(gatt: BluetoothGatt, status: Int, newState: Int) {
                if (status != BluetoothGatt.GATT_SUCCESS) {
                    setupError = IllegalStateException("Falha GATT: status=$status.")
                    servicesReady.countDown()
                    done.countDown()
                    return
                }

                if (newState == BluetoothProfile.STATE_CONNECTED) {
                    gatt.discoverServices()
                    return
                }

                if (newState == BluetoothProfile.STATE_DISCONNECTED) {
                    disconnected.set(true)
                    servicesReady.countDown()
                    done.countDown()
                }
            }

            override fun onServicesDiscovered(gatt: BluetoothGatt, status: Int) {
                if (status != BluetoothGatt.GATT_SUCCESS) {
                    setupError = IllegalStateException("Falha ao descobrir servicos: $status.")
                    servicesReady.countDown()
                    done.countDown()
                    return
                }

                val service = gatt.getService(serviceFff0)
                val notifyChar = service?.getCharacteristic(charFff4)
                val writeChar = service?.getCharacteristic(charFff5)
                if (notifyChar == null || writeChar == null) {
                    setupError = IllegalStateException("FFF4/FFF5 nao encontrados.")
                    servicesReady.countDown()
                    done.countDown()
                    return
                }

                val enabled = gatt.setCharacteristicNotification(notifyChar, true)
                if (!enabled) {
                    setupError = IllegalStateException("Nao foi possivel habilitar FFF4.")
                    servicesReady.countDown()
                    done.countDown()
                    return
                }

                val descriptor = notifyChar.getDescriptor(clientConfig)
                if (descriptor != null) {
                    descriptor.value = BluetoothGattDescriptor.ENABLE_NOTIFICATION_VALUE
                    gatt.writeDescriptor(descriptor)
                } else {
                    writeSyncCommand(gatt, writeChar)
                    servicesReady.countDown()
                }
            }

            override fun onDescriptorWrite(
                gatt: BluetoothGatt,
                descriptor: BluetoothGattDescriptor,
                status: Int,
            ) {
                val service = gatt.getService(serviceFff0)
                val writeChar = service?.getCharacteristic(charFff5)
                if (status != BluetoothGatt.GATT_SUCCESS || writeChar == null) {
                    setupError = IllegalStateException("Falha ao habilitar notify FFF4: $status.")
                    servicesReady.countDown()
                    done.countDown()
                    return
                }

                writeSyncCommand(gatt, writeChar)
                servicesReady.countDown()
            }

            override fun onCharacteristicChanged(
                gatt: BluetoothGatt,
                characteristic: BluetoothGattCharacteristic,
            ) {
                handleFff4Packet(characteristic.value, records) { total ->
                    expectedTotal = total
                }

                val total = expectedTotal
                if (total != null && records.size >= total) {
                    done.countDown()
                }
            }

            override fun onCharacteristicWrite(
                gatt: BluetoothGatt,
                characteristic: BluetoothGattCharacteristic,
                status: Int,
            ) {
                if (status != BluetoothGatt.GATT_SUCCESS) {
                    setupError = IllegalStateException("Falha ao escrever em FFF5: $status.")
                    done.countDown()
                }
            }
        }

        try {
            gattRef = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                device.connectGatt(this, false, callback, BluetoothDevice.TRANSPORT_LE)
            } else {
                device.connectGatt(this, false, callback)
            }

            if (!servicesReady.await(12, TimeUnit.SECONDS)) return null
            setupError?.let { throw it }

            done.await(25, TimeUnit.SECONDS)

            setupError?.let { throw it }
            if (bloodPressureCancelled.get() || disconnected.get()) return null
            if (records.isEmpty()) return null

            val firstIndex = records.keys.minOrNull() ?: return null
            val payload = records[firstIndex] ?: return null
            return decodeBloodPressureRecord(firstIndex, payload)
        } finally {
            try {
                gattRef?.disconnect()
            } catch (_: Throwable) {
            }
            try {
                gattRef?.close()
            } catch (_: Throwable) {
            }
        }
    }

    @SuppressLint("MissingPermission")
    private fun writeSyncCommand(
        gatt: BluetoothGatt,
        characteristic: BluetoothGattCharacteristic,
    ) {
        characteristic.writeType = BluetoothGattCharacteristic.WRITE_TYPE_DEFAULT
        characteristic.value = syncCommand
        gatt.writeCharacteristic(characteristic)
        Log.i(bloodPressureTag, "WRITE FFF5 -> 6C 37 01 00 5A")
    }

    private fun handleFff4Packet(
        raw: ByteArray?,
        records: ConcurrentHashMap<Int, ByteArray>,
        onExpectedTotal: (Int) -> Unit,
    ) {
        if (raw == null || raw.size < 2 || raw[0] != 0x33.toByte()) return

        when (raw[1].toInt() and 0xFF) {
            0x37 -> {
                if (raw.size >= 5) {
                    onExpectedTotal(raw[4].toInt() and 0xFF)
                }
            }
            0x38 -> {
                if (raw.size == 13) {
                    val idx = raw[3].toInt() and 0xFF
                    records[idx] = raw.copyOfRange(4, 12)
                }
            }
        }
    }

    private fun decodeBloodPressureRecord(index: Int, payload: ByteArray): Map<String, Any> {
        if (payload.size < 8) {
            throw IllegalStateException("Payload de afericao incompleto.")
        }

        val extra = bcdToInt(payload[5].toInt() and 0xFF)
        val systolic = if (extra >= 60) extra else 100 + extra
        val diastolic = bcdToInt(payload[6].toInt() and 0xFF)
        val bpm = payload[7].toInt() and 0xFF

        return mapOf(
            "systolic" to systolic,
            "diastolic" to diastolic,
            "bpm" to bpm,
            "recordIndex" to index,
            "rawPayload" to payload.joinToString(" ") { "%02X".format(it.toInt() and 0xFF) },
        )
    }

    private fun bcdToInt(byteValue: Int): Int {
        val hi = (byteValue shr 4) and 0x0F
        val lo = byteValue and 0x0F
        return if (hi <= 9 && lo <= 9) {
            hi * 10 + lo
        } else {
            byteValue
        }
    }
}
