import { LightningElement, api, wire, track } from 'lwc';
import { getRecord } from 'lightning/uiRecordApi';
import captureGeoFromLwc from '@salesforce/apex/ICBFS_GeoCaptureController.captureGeoFromLwc';

import visitaTemplate from './icbfs_GeoCaptureButton.html';
import iframeOnlyTemplate from './iframeOnlyTemplate.html';

const FIELDS = [
    'Visitas__c.Url_maps__c'
];

export default class IcbfsGeoCaptureButton extends LightningElement {
    @api recordId;
    @api objectApiName;
    @api availableActions = [];

    @track mapUrl;
    @track showIframeOnly = false;

    @wire(getRecord, { recordId: '$recordId', fields: FIELDS })
    wiredRecord({ error, data }) {
        if (data) {
            this.mapUrl = data.fields.Url_maps__c.value;
            // por ejemplo, activar modo iframe solo si existe mapUrl
            this.showIframeOnly = !!this.mapUrl;
        } else if (error) {
            console.error('Error fetching Url_maps__c:', error);
            this.mapUrl = null;
            this.showIframeOnly = false;
        }
    }

    render() {
        return this.showIframeOnly ? iframeOnlyTemplate : visitaTemplate;
    }

    handleClick() {
        if (navigator && navigator.geolocation) {
            navigator.geolocation.getCurrentPosition(
                (pos) => {
                    const lat = pos.coords.latitude;
                    const lon = pos.coords.longitude;
                    captureGeoFromLwc({
                        recordId: this.recordId,
                        latitude: lat,
                        longitude: lon,
                        sObjectApiName: this.objectApiName
                    })
                    .then(results => {
                        if (this.availableActions && this.availableActions.includes('FINISH')) {
                            this.dispatchEvent(new FlowNavigationFinishEvent());
                        }
                    })
                    .catch(error => {
                        console.error('Error al invocar Apex captureGeoFromLwc:', error);
                    });
                },
                (err) => {
                    console.error('Error al pedir geolocalización:', err);
                },
                { enableHighAccuracy: true, timeout: 10000 }
            );
        } else {
            console.error('Geolocalización no soportada en este navegador/contexto');
        }
        if (!this.mapUrl) {
            console.warn('No hay URL de mapa disponible para este registro.');
        }
    }
}
// import { LightningElement, api, wire, track } from 'lwc';
// import { getRecord, getFieldValue } from 'lightning/uiRecordApi';
// import captureGeoFromLwc from '@salesforce/apex/ICBFS_GeoCaptureController.captureGeoFromLwc';

// // Campos
// const FIELDS = [
//     'Visitas__c.Ubicaci_n_Tiempo_Real__Latitude__s',
//     'Visitas__c.Ubicaci_n_Tiempo_Real__Longitude__s',
//     'Visitas__c.Url_maps__c'
// ];

// export default class IcbfsGeoCaptureButton extends LightningElement {
//     @api recordId;
//     @api objectApiName;
//     @api availableActions = [];

//     @track mapUrl;

//     @wire(getRecord, { recordId: '$recordId', fields: FIELDS })
//     wiredRecord({ error, data }) {
//         if (data) {
//             const lat = getFieldValue(data, 'Visitas__c.Ubicaci_n_Tiempo_Real__Latitude__s');
//             const lon = getFieldValue(data, 'Visitas__c.Ubicaci_n_Tiempo_Real__Longitude__s');
//             const urlField = getFieldValue(data, 'Visitas__c.Url_maps__c');

//             // Priorizar la URL calculada si existe
//             if (urlField) {
//                 this.mapUrl = urlField;
//             } else if (lat != null && lon != null) {
//                 // Build embed URL on the fly (aunque idealmente ya viene de Apex)
//                 this.mapUrl = `https://www.google.com/maps/embed/v1/place?key=AIzaSyC4ObJce3_zjgNUXCSC7eSe88Tn9B-Jecs&q=${lat},${lon}`;
//             } else {
//                 this.mapUrl = null;
//             }
//         } else if (error) {
//             console.error('Error fetching record fields:', error);
//             this.mapUrl = null;
//         }
//     }

//     handleClick() {
//         if (navigator && navigator.geolocation) {
//             navigator.geolocation.getCurrentPosition(
//                 (pos) => {
//                     const lat = pos.coords.latitude;
//                     const lon = pos.coords.longitude;
//                     captureGeoFromLwc({
//                         recordId: this.recordId,
//                         latitude: lat,
//                         longitude: lon,
//                         sObjectApiName: this.objectApiName
//                     })
//                     .then(results => {
//                         // Opcional: refrescar datos después del update
//                         return refreshApex(this.wiredRecord);
//                     })
//                     .catch(error => {
//                         console.error('Error al invocar Apex captureGeoFromLwc:', error);
//                     });
//                 },
//                 (err) => {
//                     console.error('Error al pedir geolocalización:', err);
//                 },
//                 { enableHighAccuracy: true, timeout: 10000 }
//             );
//         } else {
//             console.error('Geolocalización no soportada en este navegador/contexto');
//         }

//         if (!this.mapUrl) {
//             console.warn('No hay URL de mapa disponible para este registro.');
//         }
//     }
// }