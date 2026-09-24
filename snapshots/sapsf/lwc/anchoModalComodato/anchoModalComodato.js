import { LightningElement, api } from 'lwc';

/**
 * Componente sin interfaz: ajusta el ancho del modal del Flow segun lo que necesite
 * cada pantalla.
 *
 * El modal de una Quick Action trae max-width: 950px fijo. Las pantallas con tablas o
 * catalogo de equipos necesitan mas que eso; las que solo tienen dos opciones no, y
 * estirarlas a pantalla completa se ve mal.
 *
 * Se agrega a cada pantalla del flujo indicando su tamano.
 */
const ESTILO_ID = 'comodato-modal-ancho';
const RETARDO_LIMPIEZA_MS = 800;

const TAMANOS = {
    // Formularios cortos: radio buttons, mensajes, confirmaciones.
    compacto: { ancho: '38rem' },
    // Formularios con varios campos o listas medianas.
    medio: { ancho: '60rem' },
    // Catalogo de equipos y tabla de ajuste: aprovechan toda la pantalla.
    ancho: { ancho: '95vw' }
};

export default class AnchoModalComodato extends LightningElement {
    /** compacto | medio | ancho */
    @api tamano = 'compacto';

    connectedCallback() {
        try {
            window.__comodatoAnchoRefs = (window.__comodatoAnchoRefs || 0) + 1;
            if (window.__comodatoAnchoTimer) {
                clearTimeout(window.__comodatoAnchoTimer);
                window.__comodatoAnchoTimer = null;
            }
            this.aplicarEstilo();
        } catch (e) {
            // Si el contenedor no permite inyectar estilos, el flujo sigue funcionando igual.
        }
    }

    disconnectedCallback() {
        try {
            window.__comodatoAnchoRefs = Math.max(0, (window.__comodatoAnchoRefs || 1) - 1);
            if (window.__comodatoAnchoRefs > 0) return;
            // Retardo: al pasar de una pantalla a otra hay un instante sin componente montado.
            window.__comodatoAnchoTimer = setTimeout(() => {
                if ((window.__comodatoAnchoRefs || 0) > 0) return;
                const estilo = document.getElementById(ESTILO_ID);
                if (estilo) estilo.remove();
            }, RETARDO_LIMPIEZA_MS);
        } catch (e) {
            // sin efecto
        }
    }

    aplicarEstilo() {
        const cfg = TAMANOS[this.tamano] || TAMANOS.compacto;
        const css = `
            .slds-modal__container,
            .modal-container {
                max-width: ${cfg.ancho} !important;
                width: 95% !important;
            }
        `;
        let estilo = document.getElementById(ESTILO_ID);
        if (!estilo) {
            estilo = document.createElement('style');
            estilo.id = ESTILO_ID;
            document.head.appendChild(estilo);
        }
        // Cada pantalla reescribe la regla con su propio tamano.
        estilo.textContent = css;
    }
}