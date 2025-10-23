import { LightningElement, track } from 'lwc';
import getEmbedUrlsForThreeDashboards from '@salesforce/apex/ICBFS_QuicksightEmbedController.getEmbedUrlsForThreeDashboards';

export default class ThreePanelEmbed extends LightningElement {
    @track urls;
    @track error;
    @track loading = false;

    // Puedes parametrizar los IDs vía @api si deseas permitir customización
    dashboardId1 = '7dc125a-ae4d-4306-8f73-6e212809c065';
    dashboardId2 = '7278a5e5-4249-416a-8635-aed79c4918d9';
    dashboardId3 = '5954f5c2-2bbd-4eb1-987b-941f92a023bd';

    connectedCallback() {
        this.loadEmbedUrls();
    }

    loadEmbedUrls() {
        this.loading = true;
        this.error = undefined;
        getEmbedUrlsForThreeDashboards({ 
            dashboardId1: this.dashboardId1.trim(), 
            dashboardId2: this.dashboardId2.trim(),
            dashboardId3: this.dashboardId3.trim()
        })
        .then(result => {
            this.urls = result;
        })
        .catch(err => {
            console.error('Error al obtener URLs de paneles:', err);
            this.error = err.body ? err.body.message : 'Error inesperado al cargar paneles';
        })
        .finally(() => {
            this.loading = false;
        });
    }
}