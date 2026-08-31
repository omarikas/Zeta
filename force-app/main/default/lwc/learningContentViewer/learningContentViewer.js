import { LightningElement, api } from 'lwc';

export default class LearningContentViewer extends LightningElement {
    @api materialType;
    @api materialUrl;
    @api title;

    get isYouTube() {
        return !!this.youtubeEmbedUrl;
    }

    get youtubeEmbedUrl() {
        const url = this.materialUrl || '';
        const watchMatch = url.match(/[?&]v=([^&]+)/);
        if (watchMatch) {
            return `https://www.youtube.com/embed/${watchMatch[1]}`;
        }
        const shortMatch = url.match(/youtu\.be\/([^?&]+)/);
        if (shortMatch) {
            return `https://www.youtube.com/embed/${shortMatch[1]}`;
        }
        const embedMatch = url.match(/youtube\.com\/embed\/([^?&]+)/);
        if (embedMatch) {
            return url;
        }
        return null;
    }

    get hasUrl() {
        return !!this.materialUrl;
    }

    get isPdf() {
        return this.materialType === 'PDF';
    }

    get openLabel() {
        if (this.isPdf) {
            return 'Open PDF';
        }
        if (this.materialType === 'Video') {
            return 'Open video';
        }
        return 'Open content';
    }
}