import { LightningElement, api, wire } from 'lwc';
import { getRecord, getFieldValue } from 'lightning/uiRecordApi';
import NAME_FIELD from '@salesforce/schema/Product2.Name';
import IMAGE_FIELD from '@salesforce/schema/Product2.Product_Image_URL__c';
import DISPLAY_URL_FIELD from '@salesforce/schema/Product2.DisplayUrl';
import TYPE_FIELD from '@salesforce/schema/Product2.Product_Type__c';
import BRAND_FIELD from '@salesforce/schema/Product2.Primary_Brand__c';
import STRENGTH_FIELD from '@salesforce/schema/Product2.Strength__c';
import FORM_FIELD from '@salesforce/schema/Product2.Form__c';

const FIELDS = [
    NAME_FIELD,
    IMAGE_FIELD,
    DISPLAY_URL_FIELD,
    TYPE_FIELD,
    BRAND_FIELD,
    STRENGTH_FIELD,
    FORM_FIELD
];

export default class ProductRecordImage extends LightningElement {
    @api recordId;
    imageLoadFailed = false;

    @wire(getRecord, { recordId: '$recordId', fields: FIELDS })
    product;

    get name() {
        return getFieldValue(this.product?.data, NAME_FIELD);
    }

    get imageUrl() {
        return getFieldValue(this.product?.data, IMAGE_FIELD);
    }

    get websiteUrl() {
        return getFieldValue(this.product?.data, DISPLAY_URL_FIELD);
    }

    get productType() {
        return getFieldValue(this.product?.data, TYPE_FIELD);
    }

    get brand() {
        return getFieldValue(this.product?.data, BRAND_FIELD);
    }

    get strength() {
        return getFieldValue(this.product?.data, STRENGTH_FIELD);
    }

    get form() {
        return getFieldValue(this.product?.data, FORM_FIELD);
    }

    get hasImage() {
        return Boolean(this.imageUrl) && !this.imageLoadFailed;
    }

    get subtitle() {
        return [this.productType, this.strength, this.form].filter(Boolean).join(' � ');
    }

    handleImageError() {
        this.imageLoadFailed = true;
    }
}