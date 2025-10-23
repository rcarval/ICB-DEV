import { LightningElement, track } from 'lwc';
import getEmbedUrl from '@salesforce/apex/ICBFS_QuicksightEmbedController.getEmbedUrl';
import getDashboardOptions from '@salesforce/apex/ICBFS_QuicksightEmbedController.getDashboardOptions';
import getEmbedUrlForDashboard from '@salesforce/apex/ICBFS_QuicksightEmbedController.getEmbedUrlForDashboard';

export default class EmbedDashboard extends LightningElement {
    @track embedUrl;
    @track error;
    @track loading = false;

    @track selectedValue = '';
    @track options = [];

    connectedCallback() {
        this.loadDashboardOptions();
    }

    loadDashboardOptions() {
        getDashboardOptions()
            .then(optList => {
                this.options = optList;  // Lista de objetos { label, value }
                if (this.options.length > 0) {
                    // Seleccionar la primera opción por defecto
                    this.selectedValue = this.options[0].value;
                    this.loadEmbedUrl();  // o usar un método que acepte parámetro
                }
            })
            .catch(err => {
                console.error('Error al cargar opciones de dashboards:', err);
                this.error = 'No fue posible cargar los dashboards disponibles.';
            });
    }

    loadEmbedUrl() {
        this.loading = true;
        this.error = undefined;
        getEmbedUrl()
            .then(result => {
                this.embedUrl = result;
            })
            .catch(err => {
                console.error('Error al obtener embed URL:', err);
                this.error = err.body ? err.body.message : 'Error al obtener el dashboard';
            })
            .finally(() => {
                const delayMs = 800;
                setTimeout(() => {
                    this.loading = false;
                }, delayMs);
            });
    }

handleSelectionChange(event) {
    this.selectedValue = event.detail.value;
    this.loading = true;
    this.error = undefined;
    getEmbedUrlForDashboard({ dashboardId: this.selectedValue })
        .then(result => {
            this.embedUrl = result;
        })
        .catch(err => {
            console.error('Error al obtener embed URL para dashboard:', err);
            this.error = err.body ? err.body.message : 'Error al obtener URL del dashboard seleccionado';
        })
        .finally(() => {
            const delayMs = 800;
            setTimeout(() => {
                this.loading = false;
            }, delayMs);
        });
}

    // handleReload() {
    //     this.loadEmbedUrl();
    // }
    handleReload() {
    if (this.selectedValue) {
        this.loading = true;
        this.error = undefined;
        getEmbedUrlForDashboard({ dashboardId: this.selectedValue })
            .then(result => {
                this.embedUrl = result;
            })
            .catch(err => {
                console.error('Error al recargar el panel actual:', err);
                this.error = err.body ? err.body.message : 'Error al recargar el dashboard';
            })
            .finally(() => {
                const delayMs = 800;
                setTimeout(() => {
                    this.loading = false;
                }, delayMs);
            });
    } else {
        // Si no hay valor seleccionado, quizá mostrar un mensaje o cargar por defecto
        console.warn('No hay dashboard seleccionado para recargar');
    }
}

    handleGoToUrl() {
        if (!this.selectedValue) {
            console.warn('No hay dashboard seleccionado');
            return;
        }
        // Generar una URL nueva fresca para el dashboard seleccionado y luego abrirla
        getEmbedUrlForDashboard({ dashboardId: this.selectedValue })
            .then(newUrl => {
                if (newUrl) {
                    // Abrir la nueva URL en otra pestaña
                    window.open(newUrl, '_blank');
                } else {
                    console.error('No se obtuvo URL nueva');
                }
            })
            .catch(err => {
                console.error('Error al regenerar embed URL para abrir:', err);
                this.error = err.body ? err.body.message : 'Error al regenerar URL del dashboard';
            });
    }
}
// import { LightningElement, track } from 'lwc';
// import getEmbedUrl from '@salesforce/apex/ICBFS_QuicksightEmbedController.getEmbedUrl';

// export default class EmbedDashboard extends LightningElement {
//     @track embedUrl;
//     @track error;
//     @track loading = false;

//     // Para el combobox
//     @track selectedValue = '';  // el valor seleccionado
//     @track options = [
//         { label: 'Reporte A', value: 'reportA' },
//         { label: 'Reporte B', value: 'reportB' },
//         { label: 'Reporte C', value: 'reportC' },
//         // agrega más opciones según lo que necesites
//     ];

//     connectedCallback() {
//         this.loadEmbedUrl();
//     }

//     loadEmbedUrl() {
//         this.loading = true;
//         this.error = undefined;
//         getEmbedUrl()
//             .then(result => {
//                 this.embedUrl = result;
//             })
//             .catch(err => {
//                 console.error('Error al recargar embed URL', err);
//                 this.error = err.body ? err.body.message : 'Error al obtener el dashboard';
//             })
//             .finally(() => {
//                 const delayMs = 800;
//                 setTimeout(() => {
//                     this.loading = false;
//                 }, delayMs);
//             });
//     }

//     handleReload() {
//         this.loadEmbedUrl();
//     }

//     handleGoToUrl() {
//         if (this.embedUrl) {
//             window.open(this.embedUrl, '_blank');
//         }
//     }

//     handleSelectionChange(event) {
//         this.selectedValue = event.detail.value;
//         console.log('Seleccionaste: ' + this.selectedValue);
//         // Aquí puedes hacer lo que necesites con esa selección:
//         // por ejemplo, volver a generar la URL con otro dashboard, etc.
//         // this.loadEmbedUrlFor(this.selectedValue) ...
//     }
// }
// import { LightningElement, track } from 'lwc';
// import getEmbedUrl from '@salesforce/apex/ICBFS_QuicksightEmbedController.getEmbedUrl';

// export default class EmbedDashboard extends LightningElement {
//     @track embedUrl;
//     @track error;
//     @track loading = false;

//     connectedCallback() {
//         this.loadEmbedUrl();
//     }

//     loadEmbedUrl() {
//         this.loading = true;
//         this.error = undefined;
//         getEmbedUrl()
//             .then(result => {
//                 this.embedUrl = result;
//             })
//             .catch(err => {
//                 console.error('Error al recargar embed URL', err);
//                 this.error = err.body ? err.body.message : 'Error al obtener el dashboard';
//             })
//             .finally(() => {
//             const delayMs = 5300;  // cantidad de milisegundos que quieres esperar
//             setTimeout(() => {
//                 this.loading = false;
//             }, delayMs);
//         });
//     }

//     handleReload() {
//         this.loadEmbedUrl();
//     }

//     handleStoreUrl() {
//         if (this.embedUrl) {
//             // Puedes guardarla en localStorage del navegador
//             try {
//                 window.localStorage.setItem('quicksightEmbedUrl', this.embedUrl);
//             } catch (e) {
//                 console.warn('No se pudo acceder a localStorage:', e);
//             }
//             // O simplemente mostrar un mensaje o hacer algo visual
//             console.log('Embed URL almacenada:', this.embedUrl);
//         }
//     }

//     handleGoToUrl() {
//         if (this.embedUrl) {
//             // Abrir en una nueva pestaña
//             window.open(this.embedUrl, '_blank');
//         } else {
//             console.warn('No hay URL para redirigir');
//         }
//     }
// }