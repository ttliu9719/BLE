/*
 See LICENSE folder for this sample’s licensing information.
 
 Abstract:
 A class to discover, connect, receive notifications and write data to peripherals by using a transfer service and characteristic.
 */

import UIKit
import CoreBluetooth
import os

class CentralViewController: UITableViewController {
    // UIViewController overrides, properties specific to this class, private helper methods, etc.
        
    var centralManager: CBCentralManager!
    
    var discoveredPeripherals: [UUID: CBPeripheral] = [:]

    var receivedPeripheralMessages: [UUID: String] = [:]

    var transferCharacteristic: CBCharacteristic?
    private let bluetoothQueue = DispatchQueue(label: "com.yourapp.bluetoothQueue")

    var peripheralName: String?
    // MARK: - view lifecycle
    
    override func viewDidLoad() {
        centralManager = CBCentralManager(delegate: self, queue: nil, options: [CBCentralManagerOptionShowPowerAlertKey: true])
        super.viewDidLoad()
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        // Don't keep it going while we're not showing.
        centralManager.stopScan()
        os_log("Scanning stopped")
        
        super.viewWillDisappear(animated)
    }
    
    override func numberOfSections(in tableView: UITableView) -> Int {
        return 1
    }
    
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return discoveredPeripherals.count
    }
    
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "PeripheralCell", for: indexPath)
        
        // Fetch the peripheral and message for the current indexPath
        let peripheral = Array(discoveredPeripherals.values)[indexPath.row]
        let message = receivedPeripheralMessages[peripheral.identifier]
        
        // Configure the cell with the peripheral name and received message
        cell.textLabel?.text = message
        // You might want to customize the cell further based on your needs
        
        return cell
    }
    
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        presentPeripheralNameAlert(for: Array(discoveredPeripherals.values)[indexPath.row])
    }
    
    // MARK: - Helper Methods
    
    /*
     * We will first check if we are already connected to our counterpart
     * Otherwise, scan for peripherals - specifically for our service's 128bit CBUUID
     */
    private func retrievePeripheral() {
        bluetoothQueue.async { [weak self] in
            guard let self = self else { return }
            // Retrieve a list of all connected peripherals with the transfer service
            let connectedPeripherals: [CBPeripheral] = self.centralManager.retrieveConnectedPeripherals(withServices: [TransferService.serviceUUID])
            
            if !connectedPeripherals.isEmpty {
                os_log("Found connected peripherals with transfer service: %@", connectedPeripherals)
                
                // Connect to each connected peripheral
                for connectedPeripheral in connectedPeripherals {
                    if discoveredPeripherals[connectedPeripheral.identifier] == nil {
                        os_log("Connecting to peripheral %@", connectedPeripheral)
                        self.centralManager.connect(connectedPeripheral, options: nil)
                    }
                }
            } else {
                os_log("No connected peripherals with transfer service found. Starting scanning.")
                
                // If there are no connected peripherals, start scanning for new ones
                self.centralManager.scanForPeripherals(withServices: [TransferService.serviceUUID],
                                                       options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
            }
        }
    }
    
    /*
     *  Call this when things either go wrong, or you're done with the connection.
     *  This cancels any subscriptions if there are any, or straight disconnects if not.
     *  (didUpdateNotificationStateForCharacteristic will cancel the connection if a subscription is involved)
     */
    
    private func cleanup() {
        bluetoothQueue.async { [weak self] in
            guard let self = self else { return }
            os_log("Cleaning up")
            // Loop through connected peripherals and clean up each one
            for (_, peripheral) in discoveredPeripherals {
                guard transferCharacteristic != nil else { continue }
                
                for service in (peripheral.services ?? [] as [CBService]) {
                    for characteristic in (service.characteristics ?? [] as [CBCharacteristic]) {
                        if characteristic.uuid == TransferService.characteristicUUID && characteristic.isNotifying {
                            // It is notifying, so unsubscribe
                            peripheral.setNotifyValue(false, for: characteristic)
                        }
                    }
                }
                
                // If we've gotten this far, we're connected, but we're not subscribed, so we just disconnect
                self.centralManager.cancelPeripheralConnection(peripheral)
            }
            
            // Clear the connected peripherals dictionary
            self.discoveredPeripherals.removeAll()
        }
    }
    
    func presentPeripheralNameAlert(for peripheral: CBPeripheral) {
        let alertController = UIAlertController(
            title: "Peripheral Connected, Do you want to send message to Central?",
            message: "Peripheral Name: \(String(describing: peripheral.name))",
            preferredStyle: .alert
        )
        
        let okAction = UIAlertAction(title: "OK", style: .default) { [weak self] _ in
            // After dismissing the alert, send "text" to the peripheral
            self?.sendText(to: peripheral)
        }
        
        alertController.addAction(okAction)
        present(alertController, animated: true, completion: nil)
    }
    
    private func sendText(to peripheral: CBPeripheral) {
        guard let transferCharacteristic = transferCharacteristic else { return }
        
        // Send "text" to the peripheral
        let textData = "Hello from Central!".data(using: .utf8)!
        peripheral.writeValue(textData, for: transferCharacteristic, type: .withoutResponse)
    }
}

extension CentralViewController: CBCentralManagerDelegate {
    // implementations of the CBCentralManagerDelegate methods
    
    /*
     *  centralManagerDidUpdateState is a required protocol method.
     *  Usually, you'd check for other states to make sure the current device supports LE, is powered on, etc.
     *  In this instance, we're just using it to wait for CBCentralManagerStatePoweredOn, which indicates
     *  the Central is ready to be used.
     */
    internal func centralManagerDidUpdateState(_ central: CBCentralManager) {
        
        switch central.state {
        case .poweredOn:
            // ... so start working with the peripheral
            os_log("CBManager is powered on")
            retrievePeripheral()
        case .poweredOff:
            os_log("CBManager is not powered on")
            // In a real app, you'd deal with all the states accordingly
            return
        case .resetting:
            os_log("CBManager is resetting")
            // In a real app, you'd deal with all the states accordingly
            return
        case .unauthorized:
            // In a real app, you'd deal with all the states accordingly
            if #available(iOS 13.0, *) {
                switch central.authorization {
                case .denied:
                    os_log("You are not authorized to use Bluetooth")
                case .restricted:
                    os_log("Bluetooth is restricted")
                default:
                    os_log("Unexpected authorization")
                }
            } else {
                // Fallback on earlier versions
            }
            return
        case .unknown:
            os_log("CBManager state is unknown")
            // In a real app, you'd deal with all the states accordingly
            return
        case .unsupported:
            os_log("Bluetooth is not supported on this device")
            // In a real app, you'd deal with all the states accordingly
            return
        @unknown default:
            os_log("A previously unknown central manager state occurred")
            // In a real app, you'd deal with yet unknown cases that might occur in the future
            return
        }
    }
    
    /*
     *  This callback comes whenever a peripheral that is advertising the transfer serviceUUID is discovered.
     *  We check the RSSI, to make sure it's close enough that we're interested in it, and if it is,
     *  we start the connection process
     */
    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                        advertisementData: [String: Any], rssi RSSI: NSNumber) {
        
        // Reject if the signal strength is too low to attempt data transfer.
        // Change the minimum RSSI value depending on your app’s use case.
        guard RSSI.intValue >= -50
        else {
            os_log("Discovered perhiperal not in expected range, at %d", RSSI.intValue)
            return
        }
        
        os_log("Discovered %s at %d", String(describing: peripheral.name), RSSI.intValue)
        
        // Device is in range - have we already seen it?
        if discoveredPeripherals[peripheral.identifier] == nil {
            
            // Save a local copy of the peripheral, so CoreBluetooth doesn't get rid of it.
            discoveredPeripherals[peripheral.identifier] = peripheral
            // And finally, connect to the peripheral.
            os_log("Connecting to peripheral %@", peripheral)
            centralManager.connect(peripheral, options: nil)
        }
    }
    
    private func provideHapticFeedback() {
        let feedbackGenerator = UINotificationFeedbackGenerator()
        feedbackGenerator.prepare()
        feedbackGenerator.notificationOccurred(.success)
    }
    
    /*
     *  If the connection fails for whatever reason, we need to deal with it.
     */
    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        os_log("Failed to connect to %@. %s", peripheral, String(describing: error))
        cleanup()
    }
    
    /*
     *  We've connected to the peripheral, now we need to discover the services and characteristics to find the 'transfer' characteristic.
     */
    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        os_log("Peripheral Connected")
        
        provideHapticFeedback()
        
        if discoveredPeripherals[peripheral.identifier] == nil {
            DispatchQueue.main.async {
                self.discoveredPeripherals[peripheral.identifier] = peripheral
                self.tableView.reloadData()
            }
        }
        
        // Make sure we get the discovery callbacks
        peripheral.delegate = self
        
        // Search only for services that match our UUID
        peripheral.discoverServices([TransferService.serviceUUID])
        
        // Continue scanning for other peripherals
        retrievePeripheral()
    }
    
    /*
     *  Once the disconnection happens, we need to clean up our local copy of the peripheral
     */
    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        os_log("Peripheral Disconnected: %@", peripheral.identifier.uuidString)
        
        DispatchQueue.main.async {
            self.discoveredPeripherals.removeValue(forKey: peripheral.identifier)
            self.receivedPeripheralMessages.removeValue(forKey: peripheral.identifier)
            self.tableView.reloadData()
        }
        
        // We're disconnected, so start scanning again
        // todo: update the logic maybe with timer to disconnect, add some delay
        retrievePeripheral()
    }
}

extension CentralViewController: CBPeripheralDelegate {
    // implementations of the CBPeripheralDelegate methods
    
    /*
     *  The peripheral letting us know when services have been invalidated.
     */
    func peripheral(_ peripheral: CBPeripheral, didModifyServices invalidatedServices: [CBService]) {
        
        for service in invalidatedServices where service.uuid == TransferService.serviceUUID {
            os_log("Transfer service is invalidated - rediscover services")
            peripheral.discoverServices([TransferService.serviceUUID])
        }
    }
    
    /*
     *  The Transfer Service was discovered
     */
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        if let error = error {
            os_log("Error discovering services: %s", error.localizedDescription)
            cleanup()
            return
        }
        
        // Discover the characteristic we want...
        
        // Loop through the newly filled peripheral.services array, just in case there's more than one.
        guard let peripheralServices = peripheral.services else { return }
        for service in peripheralServices {
            peripheral.discoverCharacteristics([TransferService.characteristicUUID], for: service)
        }
    }
    
    /*
     *  The Transfer characteristic was discovered.
     *  Once this has been found, we want to subscribe to it, which lets the peripheral know we want the data it contains
     */
    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        // Deal with errors (if any).
        if let error = error {
            os_log("Error discovering characteristics: %s", error.localizedDescription)
            cleanup()
            return
        }
        
        // Again, we loop through the array, just in case and check if it's the right one
        guard let serviceCharacteristics = service.characteristics else { return }
        for characteristic in serviceCharacteristics where characteristic.uuid == TransferService.characteristicUUID {
            // If it is, subscribe to it
            transferCharacteristic = characteristic
            peripheral.setNotifyValue(true, for: characteristic)
        }
        
        // Once this is complete, we just need to wait for the data to come in.
    }
    
    /*
     *   This callback lets us know more data has arrived via notification on the characteristic
     */
    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        // Deal with errors (if any)
        if let error = error {
            os_log("Error discovering characteristics: %s", error.localizedDescription)
            cleanup()
            return
        }
        
        guard let characteristicData = characteristic.value,
              let stringFromData = String(data: characteristicData, encoding: .utf8),
              let transferCharacteristic = transferCharacteristic else { return }
        
        os_log("Received %d bytes: %s", characteristicData.count, stringFromData)
        DispatchQueue.main.async {
            // Update receivedPeripheralMessages with the latest data
            self.receivedPeripheralMessages[peripheral.identifier] = stringFromData
            
            // Reload the table view to reflect the changes
            self.tableView.reloadData()
        }
        peripheral.setNotifyValue(true, for: transferCharacteristic)
    }
    
    /*
     *  The peripheral letting us know whether our subscribe/unsubscribe happened or not
     */
    func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        // Deal with errors (if any)
        if let error = error {
            os_log("Error changing notification state: %s", error.localizedDescription)
            return
        }
        
        // Exit if it's not the transfer characteristic
        guard characteristic.uuid == TransferService.characteristicUUID else { return }
        
        if characteristic.isNotifying {
            // Notification has started
            os_log("Notification began on %@", characteristic)
        } else {
            // Notification has stopped, so disconnect from the peripheral
            os_log("Notification stopped on %@. Disconnecting", characteristic)
            cleanup()
        }
        
    }
    
    /*
     *  This is called when peripheral is ready to accept more data when using write without response
     */
    func peripheralIsReady(toSendWriteWithoutResponse peripheral: CBPeripheral) {
        os_log("Peripheral is ready, send data")
    }
    
}
