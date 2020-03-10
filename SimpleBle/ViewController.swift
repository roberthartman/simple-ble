//
//  ViewController.swift
//  SimpleBle
//
//  Created by Robert Hartman on 3/5/20.
//  Copyright © 2020 SpinDance. All rights reserved.
//

import UIKit
import CoreBluetooth

private let writeServiceId = CBUUID(string: "A42E0030-06F4-43F1-8503-88AE85FFB300")
private let writeCharacteristicId = CBUUID(string: "A42E0032-06F4-43F1-8503-88AE85FFB300")
private let batteryServiceId = CBUUID(string: "180F")
private let batteryLevelCharacteristicId = CBUUID(string: "2A19")
typealias WriteCharacteristicType = UInt8

class ViewController: UIViewController {
    @IBOutlet weak var writingLabel: UILabel!
    @IBOutlet weak var didWriteLabel: UILabel!
    @IBOutlet weak var didUpdateLabel: UILabel!

    private var batteryCharacteristic: CBCharacteristic?
    private var writeCharacteristic: CBCharacteristic?
    private var savedPeripheral: CBPeripheral?
    private var writeTimer: Timer?
    private var batteryTimer: Timer?

    private let btQueue = DispatchQueue(label: "CBCentralManagerQueue")
    private lazy var centralManager: CBCentralManager = {
        CBCentralManager(delegate: self, queue: self.btQueue)
    }()
    private var writeValue: WriteCharacteristicType = 1
    private var lastWriteTime = Date()

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        if centralManager.state == .poweredOn {
            scan()
        }
    }

    private func writeToCharacteristic() {
        guard let peripheral = savedPeripheral else { logError(); return }
        guard let c = writeCharacteristic else { logError(); return }

        let value = writeValue % 2 == 0 ? 0 : writeValue

        writingLabel.text = "Writing \(value)"
        didWriteLabel.text = nil
        log(writingLabel.text ?? "")
        lastWriteTime = Date()
        peripheral.writeValue(withUnsafeBytes(of: value) { Data($0) }, for: c, type: .withResponse)
        writeValue = writeValue == 255 ? 0 : writeValue + 1
    }

    private func startWriteTimer() {
        guard writeTimer == nil || !writeTimer!.isValid else { logError(); return }

        writeTimer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true, block: { [weak self] timer in
            self?.writeToCharacteristic()
        })
    }

    private func startBatteryTimer() {
        guard batteryTimer == nil || !batteryTimer!.isValid else { logError(); return }

        batteryTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true, block: { [weak self] timer in
            guard let c = self?.batteryCharacteristic, let peripheral = self?.savedPeripheral else { logError(); return }
           peripheral.readValue(for: c)
       })
    }

    private func scan() {
        centralManager.scanForPeripherals(withServices: [writeServiceId], options: nil)
    }
}

extension ViewController: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        if central.state == .poweredOn {
            scan()
        }
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
        log("discovered")
        peripheral.delegate = self
        savedPeripheral = peripheral
        central.connect(peripheral, options: nil)
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        log("connected")
        peripheral.discoverServices(nil)
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        log()
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        log("disconnected")
        writeTimer?.invalidate()
        batteryTimer?.invalidate()
        central.connect(peripheral, options: nil)
    }

    func centralManager(_ central: CBCentralManager, connectionEventDidOccur event: CBConnectionEvent, for peripheral: CBPeripheral) {
        log()
    }


    func centralManager(_ central: CBCentralManager, didUpdateANCSAuthorizationFor peripheral: CBPeripheral) {
        log()
    }
}

extension ViewController: CBPeripheralDelegate {
    func peripheralDidUpdateName(_ peripheral: CBPeripheral) {
        log()
    }

    func peripheral(_ peripheral: CBPeripheral, didModifyServices invalidatedServices: [CBService]) {
        log()
    }

    func peripheralDidUpdateRSSI(_ peripheral: CBPeripheral, error: Error?) {
        log()
    }

    func peripheral(_ peripheral: CBPeripheral, didReadRSSI RSSI: NSNumber, error: Error?) {
        log()
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        peripheral.services?.forEach {
            peripheral.discoverCharacteristics(nil, for: $0)
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverIncludedServicesFor service: CBService, error:  Error?) {

    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard service.uuid == writeServiceId || service.uuid == batteryServiceId else {
            log("ignoring service: \(service.uuid)")
            return
        }

        DispatchQueue.main.async {
            if service.uuid == writeServiceId {
                if let c = (service.characteristics?.filter { $0.uuid == writeCharacteristicId })?.first {
                    self.writeCharacteristic = c
                    //self.startHeightTimer()
                    self.writeToCharacteristic()
                }
            } else if service.uuid == batteryServiceId {
                self.batteryCharacteristic = (service.characteristics?.filter { $0.uuid == batteryLevelCharacteristicId })?.first
                //self.startBatteryTimer()
            }
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard characteristic.service.uuid == writeServiceId else { return }

        guard error == nil else {
            didUpdateLabel.text = error!.localizedDescription
            return
        }

        guard let value = characteristic.value?.toWriteCharacteristicType else {
            logError("\(characteristic.uuid) Value is nil")
            return
        }

        DispatchQueue.main.async {
            let elapsed = Date().timeIntervalSince(self.lastWriteTime)//.rounded()
            self.didUpdateLabel.text = "didUpdate: \(value), elapsed: \(elapsed)"
            log(self.didUpdateLabel.text ?? "")

//            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                self.writeToCharacteristic()
//            }
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        guard error == nil else {
            didWriteLabel.text = error!.localizedDescription
            return
        }

        DispatchQueue.main.async {
            let elapsed = Date().timeIntervalSince(self.lastWriteTime)//.rounded()
            self.didWriteLabel.text = "didWrite, elapsed: \(elapsed)"
            log(self.didWriteLabel.text ?? "")
            peripheral.readValue(for: characteristic)
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        log()
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverDescriptorsFor characteristic: CBCharacteristic, error: Error?) {
        log()
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor descriptor: CBDescriptor, error: Error?) {
        log()
    }

    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor descriptor: CBDescriptor, error: Error?) {
        log()
    }

    func peripheralIsReady(toSendWriteWithoutResponse peripheral: CBPeripheral) {
        log()
    }

    func peripheral(_ peripheral: CBPeripheral, didOpen channel: CBL2CAPChannel?, error: Error?) {
        log()
    }
}


func log(_ message: String = "", function: String = #function, line: Int = #line) {
    print("\(function) line \(line): \(message)")
}

func logError(_ message: String = "", function: String = #function, line: Int = #line) {
    print("ERROR \(function) line \(line): \(message)")
}

extension Data {
    var toWriteCharacteristicType: WriteCharacteristicType {
        withUnsafeBytes { $0.load(as: WriteCharacteristicType.self) }
    }
}

