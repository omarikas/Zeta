import { LightningElement, wire } from 'lwc';
import getCollaborationRequests from '@salesforce/apex/CrossDeptController.getCollaborationRequests';

export default class CrossDeptCollaborationHub extends LightningElement {
    requests = [];
    error;

    @wire(getCollaborationRequests)
    wiredRequests({ data, error }) {
        if (data) {
            this.requests = data;
            this.error = undefined;
        } else if (error) {
            this.error = error.body?.message;
        }
    }

    get openRequests() {
        return (this.requests || []).filter((r) => r.status === 'Open' || r.status === 'In Progress');
    }

    get resolvedRequests() {
        return (this.requests || []).filter((r) => r.status === 'Resolved' || r.status === 'Closed');
    }
}