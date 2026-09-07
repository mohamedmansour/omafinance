// Provider registry.
//
// A watchlist entry is a "ref": either a bare symbol ("AAPL"), which belongs to
// the default provider, or a namespaced "<provider>:<id>" pair
// ("BOC:BD.CDN.5YR.DQ.YLD"). Bare symbols keep every pre-existing watchlist
// working untouched.
//
// Refs are stored uppercased, because Model.normalizeSymbol uppercases the
// whole state file. Providers must therefore accept uppercase ids; the prefix
// is matched case-insensitively.
//
// This file deliberately uses neither `.import` nor `.pragma library`: both are
// QML-only syntax that Node cannot require, and the tests require this file
// directly. Providers are injected by the QML controller via register()
// instead, which is also what keeps this file free of Yahoo/BoC specifics.

var SEPARATOR = ":";
var DEFAULT_PROVIDER = "yahoo";

var CAPABILITIES = ["search", "quote", "chart", "detail", "extendedHours"];

// Null-prototype so an id like "constructor" or "__proto__" - both of which the
// id pattern allows - cannot resolve an inherited property and be mistaken for
// an already registered provider.
var _providers = Object.create(null);
var _order = [];
var _bootstrapped = false;

function reset() {
    _providers = Object.create(null);
    _order = [];
    _bootstrapped = false;
}

// The controller registers providers on first use. The flag lives here rather
// than as a QML property because registry() is called from inside binding
// evaluation, and a binding that writes a property it also reads is a binding
// loop.
function bootstrapped() {
    return _bootstrapped;
}

function markBootstrapped() {
    _bootstrapped = true;
}

// What a capability obliges a provider to implement. Search is the one option:
// a provider either calls out for results or answers from a local catalogue.
var CONTRACT = {
    quote: [["quoteRequest"], ["parseQuotes"]],
    chart: [["chartRequest"], ["parseChart"]],
    search: [["searchRequest", "searchLocal"], ["parseSearch", "searchLocal"]],
    detail: [["detailRequests"], ["parseDetail"]]
};

// Returns a list of problems, empty when the provider is well formed. Checked at
// registration so a malformed provider names its own fault immediately, instead
// of throwing later from inside a process callback where the cause is invisible.
function validate(provider) {
    var problems = [];
    if (!provider || typeof provider !== "object")
        return ["provider must be an object"];
    if (!provider.id || typeof provider.id !== "string")
        return ["provider must have a string id"];
    // The id becomes a ref prefix, so a separator in it would break the
    // parseRef/formatRef round trip the whole registry rests on.
    if (!/^[a-z0-9_-]+$/.test(provider.id))
        return ["provider id '" + provider.id + "' must match /^[a-z0-9_-]+$/"];

    var name = provider.id;
    if (!provider.capabilities || typeof provider.capabilities !== "object") {
        problems.push(name + ": capabilities must be an object");
        return problems;
    }

    for (var i = 0; i < CAPABILITIES.length; i++) {
        var capability = CAPABILITIES[i];
        if (provider.capabilities[capability] !== true)
            continue;
        var groups = CONTRACT[capability];
        if (!groups)
            continue;
        for (var g = 0; g < groups.length; g++) {
            var alternatives = groups[g];
            var satisfied = false;
            for (var a = 0; a < alternatives.length; a++) {
                if (typeof provider[alternatives[a]] === "function")
                    satisfied = true;
            }
            if (!satisfied) {
                problems.push(name + ": capability '" + capability + "' requires "
                    + alternatives.join("() or ") + "()");
            }
        }
    }
    return problems;
}

function register(provider) {
    if (!provider || !provider.id)
        return null;
    var problems = validate(provider);
    if (!problems.length && _providers[String(provider.id).toLowerCase()])
        problems.push(provider.id + ": a provider with this id is already registered");
    if (problems.length)
        throw new Error("invalid provider - " + problems.join("; "));

    var id = String(provider.id).toLowerCase();
    if (!_providers[id])
        _order.push(id);
    _providers[id] = provider;
    return provider;
}

function providerIds() {
    return _order.slice();
}

function providers() {
    var out = [];
    for (var i = 0; i < _order.length; i++)
        out.push(_providers[_order[i]]);
    return out;
}

function provider(id) {
    return _providers[String(id || "").toLowerCase()] || null;
}

function has(id) {
    return !!provider(id);
}

// Deliberately does not fall back to an arbitrary provider: if Yahoo failed to
// construct, routing every bare symbol to whatever registered first would break
// those symbols AND collapse the other provider's own refs to bare form.
function defaultProviderId() {
    return has(DEFAULT_PROVIDER) ? DEFAULT_PROVIDER : "";
}

function defaultProvider() {
    return provider(defaultProviderId());
}

// "BOC:V80691335" -> { providerId: "boc", id: "V80691335", ref: "BOC:V80691335" }
// "AAPL"          -> { providerId: "yahoo", id: "AAPL", ref: "AAPL" }
//
// A colon that does not name a registered provider is left alone, so a symbol
// that legitimately contains one still resolves to the default provider.
function parseRef(ref) {
    var raw = String(ref || "").replace(/^\s+|\s+$/g, "");
    var fallbackId = defaultProviderId();
    if (!raw)
        return { providerId: fallbackId, id: "", ref: "", explicit: false };

    var cut = raw.indexOf(SEPARATOR);
    if (cut > 0) {
        var prefix = raw.slice(0, cut).toLowerCase();
        var rest = raw.slice(cut + 1);
        if (rest && has(prefix))
            return { providerId: prefix, id: normalizeId(prefix, rest), ref: raw, explicit: true };
    }
    return { providerId: fallbackId, id: normalizeId(fallbackId, raw), ref: raw, explicit: false };
}

// Refs are stored uppercased by the state file, so a source with lowercase ids
// folds the case back here rather than every call site remembering to.
function normalizeId(providerId, id) {
    var p = provider(providerId);
    if (p && typeof p.normalizeId === "function")
        return p.normalizeId(id);
    return id;
}

// Round-trips with parseRef. The default provider stays bare so that watchlists
// written by older versions keep the shape they already have on disk.
function formatRef(providerId, id) {
    var pid = String(providerId || "").toLowerCase();
    var body = String(id || "");
    if (!body)
        return "";
    if (!pid || pid === defaultProviderId())
        return body;
    return pid.toUpperCase() + SEPARATOR + body;
}

// Splits a "<provider>:<free text>" search query. Unlike parseRef this leaves
// the remainder exactly as typed, because a query is not an id and must not be
// put through normalizeId - uppercasing "apple" would change the request.
function parseQuery(query) {
    var raw = String(query || "").replace(/^\s+|\s+$/g, "");
    var cut = raw.indexOf(SEPARATOR);
    if (cut > 0) {
        var prefix = raw.slice(0, cut).toLowerCase();
        var rest = raw.slice(cut + 1);
        if (rest && has(prefix))
            return { providerId: prefix, term: rest };
    }
    return { providerId: defaultProviderId(), term: raw };
}

// Canonical on-disk form of a ref, so an explicitly prefixed default-provider
// entry ("YAHOO:AAPL") collapses to the bare symbol the quote map is keyed by.
function canonicalRef(ref) {
    var parsed = parseRef(ref);
    return formatRef(parsed.providerId, parsed.id);
}

function resolve(ref) {
    return provider(parseRef(ref).providerId);
}

function idFor(ref) {
    return parseRef(ref).id;
}

function capabilities(ref) {
    var p = resolve(ref);
    return (p && p.capabilities) || {};
}

function supports(ref, capability) {
    return capabilities(ref)[capability] === true;
}

// Chart ranges a provider can actually serve, in the canonical order Model
// defines. A provider that declares none is treated as supporting all of them.
function chartRangesFor(ref, canonical) {
    var all = Array.isArray(canonical) ? canonical : [];
    var p = resolve(ref);
    if (!p || typeof p.chartRanges !== "function")
        return all.slice();
    var allowed = p.chartRanges() || [];
    if (!allowed.length)
        return all.slice();
    var out = [];
    for (var i = 0; i < all.length; i++) {
        if (allowed.indexOf(all[i]) !== -1)
            out.push(all[i]);
    }
    return out.length ? out : all.slice();
}

// Splits a watchlist into one batch per provider so each can issue a single
// request. Order of first appearance is preserved to keep fetches deterministic.
function groupByProvider(refs) {
    var list = Array.isArray(refs) ? refs : [];
    var buckets = Object.create(null);
    var order = [];
    for (var i = 0; i < list.length; i++) {
        var parsed = parseRef(list[i]);
        if (!parsed.id)
            continue;
        var p = provider(parsed.providerId);
        if (!p)
            continue;
        if (!buckets[parsed.providerId]) {
            buckets[parsed.providerId] = { provider: p, providerId: parsed.providerId, refs: [], ids: [] };
            order.push(parsed.providerId);
        }
        buckets[parsed.providerId].refs.push(parsed.ref);
        buckets[parsed.providerId].ids.push(parsed.id);
    }
    var out = [];
    for (var j = 0; j < order.length; j++)
        out.push(buckets[order[j]]);
    return out;
}

// Providers return { argv: [...] }; a missing or malformed request means the
// capability is unavailable and the caller should skip the fetch entirely.
function isRequest(request) {
    return !!(request && Array.isArray(request.argv) && request.argv.length);
}

// A provider may answer with one request or several: an API that takes a single
// base currency per call cannot cover an arbitrary set of pairs in one request.
// Callers always iterate the normalised list.
function requestList(request) {
    if (!request)
        return [];
    var candidates = Array.isArray(request) ? request : [request];
    var out = [];
    for (var i = 0; i < candidates.length; i++) {
        if (isRequest(candidates[i]))
            out.push(candidates[i]);
    }
    return out;
}

if (typeof module !== "undefined") {
    module.exports = {
        SEPARATOR: SEPARATOR,
        DEFAULT_PROVIDER: DEFAULT_PROVIDER,
        CAPABILITIES: CAPABILITIES,
        reset: reset,
        bootstrapped: bootstrapped,
        markBootstrapped: markBootstrapped,
        register: register,
        validate: validate,
        CONTRACT: CONTRACT,
        providerIds: providerIds,
        providers: providers,
        provider: provider,
        has: has,
        defaultProviderId: defaultProviderId,
        defaultProvider: defaultProvider,
        parseRef: parseRef,
        parseQuery: parseQuery,
        canonicalRef: canonicalRef,
        formatRef: formatRef,
        resolve: resolve,
        idFor: idFor,
        capabilities: capabilities,
        supports: supports,
        chartRangesFor: chartRangesFor,
        groupByProvider: groupByProvider,
        isRequest: isRequest,
        requestList: requestList
    };
}
