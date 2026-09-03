let toastContainerEl = null;

function ensureToastContainer() {
    if (toastContainerEl && document.body.contains(toastContainerEl)) {
        return toastContainerEl;
    }
    toastContainerEl = document.createElement('div');
    toastContainerEl.id = 'toast-container';
    toastContainerEl.className = 'toast-container';
    document.body.appendChild(toastContainerEl);
    return toastContainerEl;
}

function escapeHtml(str) {
    if (!str) return '';
    return String(str)
        .replace(/&/g, '&amp;')
        .replace(/</g, '&lt;')
        .replace(/>/g, '&gt;')
        .replace(/"/g, '&quot;')
        .replace(/'/g, '&#039;');
}

export function showToast({ title = '', message = '', variant = 'info', mode = 'dismissible', duration }) {
    if (typeof document === 'undefined') return;
    const container = ensureToastContainer();

    const toastItem = document.createElement('div');
    const variantClass = `toast-${variant || 'info'}`;
    toastItem.className = `toast-item ${variantClass}`;

    let iconSymbol = 'i';
    if (variant === 'success') iconSymbol = '✓';
    else if (variant === 'error') iconSymbol = '✕';
    else if (variant === 'warning') iconSymbol = '!';

    toastItem.innerHTML = `
        <span class="toast-icon" aria-hidden="true">${iconSymbol}</span>
        <div class="toast-content">
            ${title ? `<div class="toast-title">${escapeHtml(title)}</div>` : ''}
            ${message ? `<div class="toast-message">${escapeHtml(message)}</div>` : ''}
        </div>
        <button type="button" class="toast-close" title="Close notification" aria-label="Close">×</button>
    `;

    const closeBtn = toastItem.querySelector('.toast-close');
    const dismiss = () => {
        if (toastItem.classList.contains('toast-hiding')) return;
        toastItem.classList.add('toast-hiding');
        setTimeout(() => {
            if (toastItem.parentNode) {
                toastItem.parentNode.removeChild(toastItem);
            }
        }, 250);
    };

    if (closeBtn) {
        closeBtn.addEventListener('click', dismiss);
    }
    container.appendChild(toastItem);

    if (mode !== 'sticky') {
        const timeoutMs = duration || (variant === 'error' ? 7000 : 4000);
        setTimeout(dismiss, timeoutMs);
    }
}

export function setupToastListener() {
    if (typeof window === 'undefined') return;

    const handleToastEvent = (event) => {
        const detail = event.detail || {};
        if (detail.title || detail.message) {
            showToast(detail);
        }
    };

    window.addEventListener('lightning__showtoast', handleToastEvent, true);
    document.addEventListener('lightning__showtoast', handleToastEvent, true);
}
