import { LightningElement, api, wire } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getSessionDetail from '@salesforce/apex/ClmMetricsController.getSessionDetail';
import getSessionMessageResponses from '@salesforce/apex/ClmMetricsController.getSessionMessageResponses';
import saveMessageResponses from '@salesforce/apex/ClmMetricsController.saveMessageResponses';
import { getLocalSession } from 'c/clmOfflineStore';
import { isOfflineMode, queueOfflineAction } from 'c/clmOfflineSync';

const DEFAULT_MESSAGES = ['EFFICACY', 'INDICATION', 'SAFETY', 'SIDE EFFECTS', 'USAGE'];
const SENTIMENTS = [
    { label: 'Negative', value: 'Negative', position: 0 },
    { label: 'Neutral', value: 'Neutral', position: 50 },
    { label: 'Positive', value: 'Positive', position: 100 }
];

export default class ClmMessageFeedback extends LightningElement {
    @api sessionId;

    productName = 'ADRAVIL-DETAIL';
    productImageUrl;
    topics = [];
    isSaving = false;

    connectedCallback() {
        if (isOfflineMode()) {
            this.loadOfflineSession();
        }
    }

    async loadOfflineSession() {
        const local = await getLocalSession(this.sessionId);
        const data = local?.session;
        if (!data) {
            return;
        }
        const messages = new Set();
        (data.sequences || []).forEach((seq) => {
            (seq.messageNames || '')
                .split(/[;,]/)
                .map((item) => item.trim())
                .filter(Boolean)
                .forEach((msg) => messages.add(msg.toUpperCase()));
        });
        const topicNames = messages.size ? Array.from(messages) : DEFAULT_MESSAGES;
        this.productName =
            data.productName ||
            data.sequences?.[0]?.productNames?.split(/[;,]/)[0]?.trim() ||
            this.productName;
        this.productImageUrl = data.productImageUrl;
        this.initializeTopics(topicNames);
        const responses = local?.messageResponses || data.messageResponses || [];
        if (responses.length) {
            const responseMap = {};
            responses.forEach((row) => {
                responseMap[row.messageName] = row.sentiment;
            });
            this.topics = this.topics.map((topic) => ({
                ...topic,
                selected: !!responseMap[topic.name],
                sentiment: responseMap[topic.name] || topic.sentiment,
                sliderStyle: this.buildSliderStyle(responseMap[topic.name] || topic.sentiment)
            }));
        }
    }

    @wire(getSessionDetail, { sessionId: '$sessionId' })
    wiredSession({ data }) {
        if (!data) {
            return;
        }
        const messages = new Set();
        (data.sequences || []).forEach((seq) => {
            (seq.messageNames || '')
                .split(/[;,]/)
                .map((item) => item.trim())
                .filter(Boolean)
                .forEach((msg) => messages.add(msg.toUpperCase()));
        });
        const topicNames = messages.size ? Array.from(messages) : DEFAULT_MESSAGES;
        this.productName =
            data.productName ||
            data.sequences?.[0]?.productNames?.split(/[;,]/)[0]?.trim() ||
            this.productName;
        this.productImageUrl = data.productImageUrl;
        this.initializeTopics(topicNames);
    }

    @wire(getSessionMessageResponses, { sessionId: '$sessionId' })
    wiredResponses({ data }) {
        if (!data || !this.topics.length) {
            return;
        }
        const responseMap = {};
        data.forEach((row) => {
            responseMap[row.messageName] = row.sentiment;
        });
        this.topics = this.topics.map((topic) => ({
            ...topic,
            selected: !!responseMap[topic.name],
            sentiment: responseMap[topic.name] || topic.sentiment,
            sliderStyle: this.buildSliderStyle(responseMap[topic.name] || topic.sentiment)
        }));
    }

    initializeTopics(topicNames) {
        this.topics = topicNames.map((name, index) => ({
            key: `${name}_${index}`,
            name,
            selected: false,
            sentiment: null,
            sliderStyle: 'left: 0%',
            canRemove: false
        }));
    }

    handleTopicToggle(event) {
        const name = event.target.dataset.name;
        this.topics = this.topics.map((topic) => {
            if (topic.name !== name) {
                return topic;
            }
            const selected = event.target.checked;
            return {
                ...topic,
                selected,
                sentiment: selected ? topic.sentiment || 'Neutral' : null,
                sliderStyle: selected
                    ? this.buildSliderStyle(topic.sentiment || 'Neutral')
                    : 'left: 0%',
                canRemove: selected
            };
        });
    }

    handleSentimentChange(event) {
        const name = event.currentTarget.dataset.name;
        const sentiment = event.currentTarget.dataset.sentiment;
        this.topics = this.topics.map((topic) =>
            topic.name === name
                ? {
                      ...topic,
                      selected: true,
                      sentiment,
                      sliderStyle: this.buildSliderStyle(sentiment),
                      canRemove: true
                  }
                : topic
        );
    }

    handleRemove(event) {
        const name = event.currentTarget.dataset.name;
        this.topics = this.topics.map((topic) =>
            topic.name === name
                ? {
                      ...topic,
                      selected: false,
                      sentiment: null,
                      sliderStyle: 'left: 0%',
                      canRemove: false
                  }
                : topic
        );
    }

    buildSliderStyle(sentiment) {
        const point = SENTIMENTS.find((item) => item.value === sentiment);
        return `left: ${point ? point.position : 50}%`;
    }

    get sentimentOptions() {
        return SENTIMENTS;
    }

    async handleSave() {
        if (!this.sessionId) {
            return;
        }
        const responses = this.topics
            .filter((topic) => topic.selected && topic.sentiment)
            .map((topic, index) => ({
                productName: this.productName,
                messageName: topic.name,
                sentiment: topic.sentiment,
                sortOrder: index + 1
            }));
        this.isSaving = true;
        try {
            // Note: navigator.onLine is unreliable in Capacitor WebView
            // Always try to save - let network failures be handled gracefully
            if (
                this.sessionId &&
                /^[a-zA-Z0-9]{15}$|^[a-zA-Z0-9]{18}$/.test(String(this.sessionId))
            ) {
                await saveMessageResponses({ sessionId: this.sessionId, responses });
            } else {
                await queueOfflineAction({
                    actionType: 'SAVE_MESSAGE_RESPONSES',
                    clientSessionKey: this.sessionId,
                    responsesJson: JSON.stringify(responses)
                });
            }
            this.dispatchEvent(new CustomEvent('saved'));
        } catch (error) {
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Save failed',
                    message: error?.body?.message || error?.message,
                    variant: 'error'
                })
            );
        } finally {
            this.isSaving = false;
        }
    }

    handleCancel() {
        this.dispatchEvent(new CustomEvent('cancel'));
    }
}