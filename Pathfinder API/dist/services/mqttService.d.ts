import mqtt from 'mqtt';
export declare let mqttClient: mqtt.MqttClient;
export declare const initializeMqtt: () => void;
export declare const publishCommand: (deviceId: string, command: string, payload?: any) => void;
export declare const clearDeviceCache: (deviceId: string) => void;
export declare const triggerAlert: (data: any) => Promise<void>;
//# sourceMappingURL=mqttService.d.ts.map