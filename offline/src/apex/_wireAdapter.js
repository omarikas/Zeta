// Dual-mode Apex stand-in for the offline build.
//
// Real @salesforce/apex imports are BOTH imperatively callable (`method(params)`
// returns a Promise) AND usable as an LWC `@wire` adapter. A plain async function
// is not constructable, so `@wire(asyncFn)` throws ("not a constructor"). This
// factory returns a function that works both ways:
//   - called normally  -> runs the loader (or resolves null) and returns a Promise
//   - `new`-ed by @wire -> a WireAdapter (connect/update/disconnect) that emits
//     the loader result, or an error so consumers fall back to their offline path
//     instead of spinning forever.
export function makeDualApex(loader) {
    function ApexDual(arg) {
        if (this instanceof ApexDual) {
            // Wire mode: engine does `new ApexDual(dataCallback)`.
            this._dataCallback = arg;
            this._config = undefined;
            return;
        }
        // Imperative mode: `ApexDual(params)` -> Promise.
        return loader ? Promise.resolve(loader(arg)) : Promise.resolve(null);
    }

    ApexDual.prototype.connect = function connect() {
        this._emit();
    };
    ApexDual.prototype.update = function update(config) {
        this._config = config;
        this._emit();
    };
    ApexDual.prototype.disconnect = function disconnect() {
        this._dataCallback = null;
    };
    ApexDual.prototype._emit = function _emit() {
        const cb = this._dataCallback;
        if (!cb) {
            return;
        }
        if (loader) {
            Promise.resolve(loader(this._config)).then(
                (data) => cb({ data, error: undefined }),
                (error) => cb({ data: undefined, error })
            );
        } else {
            // No offline data source — surface as an error so @wire consumers
            // take their error/empty branch rather than an infinite spinner.
            cb({
                data: undefined,
                error: { status: 0, body: { message: 'Not available in the offline build.' } }
            });
        }
    };

    return ApexDual;
}

// Default export: no loader — imperative resolves null, wire emits an error.
export default makeDualApex();
