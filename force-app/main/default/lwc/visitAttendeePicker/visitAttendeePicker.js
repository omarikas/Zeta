import { LightningElement, api } from 'lwc';

export default class VisitAttendeePicker extends LightningElement {
    @api visitId;
    @api attendees = [];
    @api disabled = false;

    pickerOpen = false;

    get displayAttendees() {
        return (this.attendees || []).map((row) => ({
            ...row,
            chipClass: row.isPrimary ? 'attendee-chip attendee-chip-primary' : 'attendee-chip',
            key: row.id || row.accountId
        }));
    }

    get hasAttendees() {
        return this.displayAttendees.length > 0;
    }

    handleOpenPicker() {
        if (!this.disabled) {
            this.pickerOpen = true;
        }
    }

    handleClosePicker() {
        this.pickerOpen = false;
    }

    handlePickerSelect(event) {
        const { candidate } = event.detail;
        const exists = (this.attendees || []).some((row) => row.accountId === candidate.accountId);
        if (exists) {
            return;
        }
        const next = [
            ...(this.attendees || []),
            {
                accountId: candidate.accountId,
                accountName: candidate.accountName,
                specialty: candidate.specialty,
                recordTypeDeveloperName: candidate.recordTypeDeveloperName,
                accountTypeLabel: candidate.accountTypeLabel,
                role: 'Attendee',
                isPrimary: false,
                displayOrder: (this.attendees || []).length + 1
            }
        ];
        this.emitChange(next);
        this.pickerOpen = false;
    }

    handleRemove(event) {
        const accountId = event.currentTarget.dataset.id;
        const target = (this.attendees || []).find((row) => row.accountId === accountId);
        if (target?.isPrimary) {
            return;
        }
        const next = (this.attendees || []).filter((row) => row.accountId !== accountId);
        this.emitChange(next);
    }

    emitChange(attendees) {
        this.dispatchEvent(
            new CustomEvent('attendeeschange', {
                detail: { attendees },
                bubbles: true,
                composed: true
            })
        );
    }
}