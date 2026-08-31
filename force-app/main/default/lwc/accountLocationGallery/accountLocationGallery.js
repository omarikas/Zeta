import { LightningElement, api, wire } from 'lwc';
import { refreshApex } from '@salesforce/apex';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getLocationMedia from '@salesforce/apex/AccountMapsPlacesService.getLocationMedia';
import enrichAccount from '@salesforce/apex/AccountMapsPlacesService.enrichAccount';

export default class AccountLocationGallery extends LightningElement {
    @api recordId;

    isBusy = false;
    errorMessage;
    wiredMedia;

    @wire(getLocationMedia, { accountId: '$recordId' })
    wiredGetMedia(result) {
        this.wiredMedia = result;
        if (result.error) {
            this.errorMessage = this.reduceError(result.error);
        } else {
            this.errorMessage = undefined;
        }
    }

    get media() {
        return this.wiredMedia?.data;
    }

    get isLoading() {
        return !this.wiredMedia || (this.wiredMedia.data === undefined && !this.wiredMedia.error);
    }

    get mapsPhone() {
        return this.media?.mapsPhone;
    }

    get mapsPhoneHref() {
        return this.mapsPhone ? `tel:${this.mapsPhone}` : null;
    }

    get addressLine() {
        return this.media?.addressLine;
    }

    get message() {
        return this.media?.message;
    }

    get streetViewUrl() {
        return this.media?.streetViewUrl;
    }

    get staticMapUrl() {
        return this.media?.staticMapUrl;
    }

    get photoUrls() {
        return this.media?.photoUrls || [];
    }

    get mapMarkers() {
        if (this.media?.latitude == null || this.media?.longitude == null) {
            return [];
        }
        return [
            {
                location: {
                    Latitude: this.media.latitude,
                    Longitude: this.media.longitude
                },
                title: this.media.accountName || 'Account',
                description: this.media.addressLine || ''
            }
        ];
    }

    get hasMapMarkers() {
        return this.mapMarkers.length > 0;
    }

    async handleEnrich() {
        if (!this.recordId || this.isBusy) {
            return;
        }
        this.isBusy = true;
        try {
            const result = await enrichAccount({ accountId: this.recordId });
            this.dispatchEvent(
                new ShowToastEvent({
                    title: result?.status || 'Maps enrichment',
                    message: result?.phone
                        ? `Maps phone: ${result.phone}`
                        : result?.message || 'No phone found',
                    variant: result?.phone ? 'success' : 'info'
                })
            );
            await refreshApex(this.wiredMedia);
        } catch (e) {
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Maps enrichment failed',
                    message: this.reduceError(e),
                    variant: 'error'
                })
            );
        } finally {
            this.isBusy = false;
        }
    }

    reduceError(error) {
        if (!error) {
            return 'Unknown error';
        }
        if (Array.isArray(error.body)) {
            return error.body.map((e) => e.message).join(', ');
        }
        if (typeof error.body?.message === 'string') {
            return error.body.message;
        }
        return error.message || 'Unknown error';
    }
}