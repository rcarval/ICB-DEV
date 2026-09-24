import { LightningElement, track } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import searchKeywordInChats from '@salesforce/apex/seidor_WhatsAppFiltro.searchKeywordInChats';
import getConversationMessages from '@salesforce/apex/seidor_WhatsAppFiltro.getConversationMessages';

export default class Seidor_WhatsappBusqueda extends NavigationMixin(LightningElement) {
    @track searchTerm = '';
    @track searchedTerm = '';
    @track results = [];
    @track isLoading = false;
    @track hasSearched = false;

    @track isModalOpen = false;
    @track isModalLoading = false;
    @track chatMessages = [];

    handleInputChange(event) {
        this.searchTerm = event.target.value;
    }

    handleKeyUp(event) {
        if (event.key === 'Enter') {
            this.handleSearch();
        }
    }

    handleSearch() {
        if (!this.searchTerm || this.searchTerm.trim().length < 2) {
            return;
        }

        this.isLoading = true;
        this.hasSearched = true;
        this.searchedTerm = this.searchTerm.trim();
        this.results = [];

        searchKeywordInChats({ searchTerm: this.searchedTerm, limitSessions: 30 })
            .then((data) => this.attachRecordUrls(data))
            .then((data) => {
                this.results = data;
            })
            .catch((error) => {
                console.error('Error al buscar:', error);
            })
            .finally(() => {
                this.isLoading = false;
            });
    }

    attachRecordUrls(data) {
        if (!data || data.length === 0) return [];

        const urlPromises = data.map((row) =>
            this[NavigationMixin.GenerateUrl]({
                type: 'standard__recordPage',
                attributes: {
                    recordId: row.sessionId,
                    objectApiName: 'MessagingSession',
                    actionName: 'view'
                }
            })
                .then((url) => ({ ...row, recordUrl: url }))
                .catch(() => ({ ...row, recordUrl: '#' }))
        );

        return Promise.all(urlPromises);
    }

    navigateToSession(event) {
        event.preventDefault();
        const sessionId = event.currentTarget.dataset.id;
        this[NavigationMixin.Navigate]({
            type: 'standard__recordPage',
            attributes: {
                recordId: sessionId,
                objectApiName: 'MessagingSession',
                actionName: 'view'
            }
        });
    }

    get hasResults() {
        return this.results && this.results.length > 0;
    }

    get noResultsFound() {
        return this.hasSearched && !this.isLoading && (!this.results || this.results.length === 0);
    }

    get hasChatMessages() {
        return this.chatMessages && this.chatMessages.length > 0;
    }

    openChat(event) {
        const sessionId = event.currentTarget.dataset.id;
        this.currentEndUserName = event.currentTarget.dataset.enduser || 'Cliente';
        this.isModalOpen = true;
        this.isModalLoading = true;
        this.chatMessages = [];

        getConversationMessages({ sessionId })
            .then((data) => {
                this.chatMessages = data.map((m) => ({
                    ...m,
                    rowClass: this.rowClassForRole(m.senderRole),
                    bubbleClass: this.bubbleClassForRole(m.senderRole),
                    senderLabel: this.buildSenderLabel(m.senderRole),
                    highlightedText: this.highlightMatch(m.messageText, this.searchedTerm)
                }));
            })
            .catch((error) => {
                console.error('Error al obtener el chat:', error);
            })
            .finally(() => {
                this.isModalLoading = false;
            });
    }

    closeModal() {
        this.isModalOpen = false;
        this.chatMessages = [];
    }

    rowClassForRole(role) {
        if (role === 'EndUser') return 'chat-row chat-row_left';
        if (role === 'System') return 'chat-row chat-row_center';
        return 'chat-row chat-row_right';
    }

    bubbleClassForRole(role) {
        if (role === 'EndUser') return 'chat-bubble chat-bubble_enduser';
        if (role === 'Agent') return 'chat-bubble chat-bubble_agent';
        if (role === 'Chatbot') return 'chat-bubble chat-bubble_bot';
        return 'chat-bubble chat-bubble_system';
    }

    buildSenderLabel(role) {
        if (role === 'EndUser') return `${this.currentEndUserName} · Usuario`;
        if (role === 'Agent') return 'Agente';
        if (role === 'Chatbot') return 'Chatbot';
        return 'Sistema';
    }

    escapeHtml(text) {
        return text
            .replace(/&/g, '&amp;')
            .replace(/</g, '&lt;')
            .replace(/>/g, '&gt;');
    }

    highlightMatch(text, term) {
        if (!text) return '';
        const safeText = this.escapeHtml(text);
        if (!term) return safeText;

        const safeTerm = this.escapeHtml(term).replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
        const regex = new RegExp('(' + safeTerm + ')', 'gi');
        return safeText.replace(regex, '<mark>$1</mark>');
    }
}