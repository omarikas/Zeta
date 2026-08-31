import { LightningElement, api } from 'lwc';

export default class ProductThumbnail extends LightningElement {
    @api imageUrl;
    @api productName;
    @api size = 'sm';

    imageLoadFailed = false;

    get hasImage() {
        return Boolean(this.imageUrl) && !this.imageLoadFailed;
    }

    get containerClass() {
        return `thumb-container thumb-${this.size}`;
    }

    get altText() {
        return this.productName ? `${this.productName} product image` : 'Product image';
    }

    handleImageError() {
        this.imageLoadFailed = true;
    }
}