import Alamofire
import ESPProvision

class EspDevice {
  static let shared = EspDevice()
  var espDevice: ESPDevice?
  func setDevice(device: ESPDevice) {
    self.espDevice = device
  }
}


@objc(EspIdfProvisioning)
class EspIdfProvisioning: NSObject {
    private var security: ESPSecurity = .secure

    var bleDevices:[ESPDevice]?

    @objc(createDevice:devicePassword:deviceProofOfPossession:successCallback:)
    func createDevice(_ deviceName: String, devicePassword: String, deviceProofOfPossession: String, successCallback: @escaping RCTResponseSenderBlock) -> Void {
      ESPProvisionManager.shared.createESPDevice(
          deviceName: deviceName,
          transport: ESPTransport.softap,
          security: ESPSecurity.secure,
          proofOfPossession: deviceProofOfPossession,
          softAPPassword: devicePassword
      ){ espDevice, _ in
          dump(espDevice)
          EspDevice.shared.setDevice(device: espDevice!)
          successCallback([nil, "success"])
      }

    }

    // Searches for BLE devices with a name starting with the given prefix.
    // The prefix must match the string in '/main/app_main.c'
    // Resolves to an array of BLE devices
    @objc(getBleDevices:withResolver:withRejecter:)
    func getBleDevices(prefix: String, resolve: @escaping RCTPromiseResolveBlock, reject: @escaping RCTPromiseRejectBlock) -> Void {

      ESPProvisionManager.shared.searchESPDevices(devicePrefix:prefix, transport:.ble) { bleDevices, error in
        DispatchQueue.main.async {
          if bleDevices == nil {
            let error = NSError(domain: "getBleDevices", code: 404, userInfo: [NSLocalizedDescriptionKey : "No devices found"])
            reject("404", "getBleDevices", error)

            return
          }

          let deviceNames = bleDevices!.map {[
            "name": $0.name,
          ]}

          resolve(deviceNames)
        }
      }
    }

    // Connects to a BLE device
    // We need the Service UUID from the config.service_uuid in app_prov.c
    // We need the proof of possestion (pop) specified in '/main/app_main.c'
    // The deviceAddress is the address we got from the "getBleDevices" function
    // Resolves when connected to device
    @objc(connectBleDevice:security:deviceProofOfPossession:withResolver:withRejecter:)
    func connectBleDevice(deviceAddress: String, security: Int = 1, deviceProofOfPossession: String? = nil, resolve: @escaping RCTPromiseResolveBlock, rejecter reject: @escaping RCTPromiseRejectBlock) -> Void {
        
        ESPProvisionManager.shared.createESPDevice(deviceName: deviceAddress, transport: .ble, security: security == 1 ? .secure : .unsecure, proofOfPossession: deviceProofOfPossession, completionHandler: { device, _ in
          if device == nil {
            let error = NSError(domain: "connectBleDevice", code: 400, userInfo: [NSLocalizedDescriptionKey : "Device not found"])
            reject("400", "Device not found", error)

            return
          }

          let espDevice: ESPDevice = device!
          EspDevice.shared.setDevice(device: espDevice)

          espDevice.connect(completionHandler: { status in

            switch status {
              case .connected:
                  let response: [String: Any] = [
                    "name": espDevice.name,
                    "advertisementData": espDevice.advertisementData ?? {},
                    "capabilities": espDevice.capabilities ?? [],
                    "versionInfo": espDevice.versionInfo ?? {}
                  ]
                  resolve(response)
              case let .failedToConnect(error):
                  reject("400", "Failed to connect", error)
              default:
                let error = NSError(domain: "connectBleDevice", code: 400, userInfo: [NSLocalizedDescriptionKey : "Default connection error"])
                reject("400", "Default connection error", error)
            }
          })
      })
    }

    @objc(scanWifiList:withRejecter:)
    func scanWifiList(resolve: @escaping RCTPromiseResolveBlock, rejecter reject: @escaping RCTPromiseRejectBlock) -> Void {
      EspDevice.shared.espDevice?.scanWifiList{ wifiList, _ in

        let networks = wifiList!.map {[
            "name": $0.ssid,
            "rssi": $0.rssi,
            "security": $0.auth.rawValue,
        ]}

        resolve(networks)
      }
    }
    
    @objc(provision:passPhrase:withResolver:withRejecter:)
    func provision(ssid: String, passPhrase: String, resolve: @escaping RCTPromiseResolveBlock, rejecter reject: @escaping RCTPromiseRejectBlock) -> Void {
        var completedFlag = false
        EspDevice.shared.espDevice?.provision(ssid: ssid, passPhrase: passPhrase, completionHandler: {
            status in
            dump(status)
            if(!completedFlag) {
                completedFlag = true
                switch status {
                case .configApplied, .success:
                    resolve(nil)
                default:
                    let error = NSError(domain: "Failed to connect", code: 400, userInfo: [NSLocalizedDescriptionKey : "Default connection error"])
                    reject("400", "FAILED", error)                    
                }
                
            }
            
        })
    }
    
}
