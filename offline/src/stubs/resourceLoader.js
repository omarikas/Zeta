export async function loadScript(_component, src) {
    if (typeof document === 'undefined') return;
    const existing = document.querySelector(`script[src="${src}"]`);
    if (existing) return;
    return new Promise((resolve, reject) => {
        const script = document.createElement('script');
        script.src = src;
        script.async = true;
        script.onload = () => resolve();
        script.onerror = () => reject(new Error(`Failed to load script: ${src}`));
        document.head.appendChild(script);
    });
}

export async function loadStyle(_component, href) {
    if (typeof document === 'undefined') return;
    const existing = document.querySelector(`link[href="${href}"]`);
    if (existing) return;
    return new Promise((resolve, reject) => {
        const link = document.createElement('link');
        link.rel = 'stylesheet';
        link.href = href;
        link.onload = () => resolve();
        link.onerror = () => reject(new Error(`Failed to load style: ${href}`));
        document.head.appendChild(link);
    });
}
