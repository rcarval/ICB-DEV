/**
 * ICBFD_FlowActionButtons
 * Autor: José
 * Fecha: 2026-02-19
 */
import { LightningElement, api } from 'lwc';
import { FlowAttributeChangeEvent, FlowNavigationNextEvent } from 'lightning/flowSupport';

export default class ICBFD_FlowActionButtons extends LightningElement {
  // Textos
  @api title = 'Elige una acción';
  @api helperText;

  // Labels
  @api scanLabel = 'Registrar escaneo';
  @api prodLabel = 'Agregar producto';

  // Valores que se escribirán en el Flow (deben calzar con DEC_Accion: SCAN / PRODUCTO)
  @api scanValue = 'SCAN';
  @api prodValue = 'PRODUCTO';

  // Iconos SLDS
  @api scanIcon = 'utility:scan';
  @api prodIcon = 'utility:add';

  // Avanzar automáticamente
  @api autoAdvance = false;

  // Output a Flow (bindéalo a varAccion)
  @api value;

  get isScanSelected() {
    return this.value === this.scanValue;
  }

  get isProdSelected() {
    return this.value === this.prodValue;
  }

  get scanButtonVariant() {
    return this.isScanSelected ? 'brand' : 'neutral';
  }

  get prodButtonVariant() {
    return this.isProdSelected ? 'brand' : 'neutral';
  }

  handleScan() {
    this.setValue(this.scanValue);
  }

  handleProd() {
    this.setValue(this.prodValue);
  }

  setValue(newValue) {
    this.value = newValue;

    // Notifica al Flow
    this.dispatchEvent(new FlowAttributeChangeEvent('value', this.value));

    // Opcional: avanzar automáticamente
    if (this.autoAdvance) {
      this.dispatchEvent(new FlowNavigationNextEvent());
    }
  }
}