/**
ICB Food Service
Desarrollado por: José Illanes
Fecha: 2026-02-12
Descripción: Landing QR (Experience Cloud LWR) que lee ?token= desde la URL
             y ejecuta el Screen Flow pasando varToken.
*/
import { LightningElement, track } from 'lwc';

export default class IcbfsQrLandingLwr extends LightningElement {
    @track loading = true;
    @track token;
    @track inputVariables = [];

    // ⚠️ Pon el API Name REAL del Flow (no el label).
    // Ejemplo típico (por tu XML / nombre): QR_pantalla_se_accion
    flowApiName = 'QR_pantalla_se_accion';

    connectedCallback() {
        const params = new URLSearchParams(window.location.search);
        this.token = params.get('token');

        if (this.token) {
            this.inputVariables = [
                { name: 'varToken', type: 'String', value: this.token }
            ];
        }

        this.loading = false;
    }
}