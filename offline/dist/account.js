// Account page is now a thin redirect to the generic record view, so accounts
// render through the same Salesforce UI API page-layout path as every other
// object (see record.js). Preserves the record id from either ?accountId= or ?id=.
function redirectToGenericRecord() {
    const params = new URLSearchParams(window.location.search);
    const id = params.get('accountId') || params.get('id') || params.get('recordId');
    if (!id) {
        const bar = document.getElementById('account-error');
        if (bar) {
            bar.textContent = 'No account specified. Go back and select an account.';
            bar.style.display = 'block';
        }
        const loading = document.getElementById('account-loading');
        if (loading) loading.style.display = 'none';
        return;
    }
    const target = `/record.html?object=Account&recordId=${encodeURIComponent(id)}`;
    // replace() so the browser back button skips this redirect hop.
    window.location.replace(target);
}

document.addEventListener('DOMContentLoaded', redirectToGenericRecord);
