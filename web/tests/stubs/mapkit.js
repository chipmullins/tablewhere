// Test stub for MapKit JS (cdn.apple-mapkit.com/mk/5.x.x/mapkit.core.js).
// window.__mk.places[query] (or "__poi" for the category lookup) = places;
// window.__mk.delay[query] = ms; window.__mk.calls counts searches.
(function () {
  const state = window.__mk = window.__mk || {};
  state.places = state.places || {};
  state.delay = state.delay || {};
  state.calls = state.calls || [];
  state.annotations = state.annotations || [];
  state.fits = 0;

  class Coordinate { constructor(latitude, longitude) { this.latitude = latitude; this.longitude = longitude; } }
  class CoordinateSpan { constructor(a, b) { this.latitudeDelta = a; this.longitudeDelta = b; } }
  class CoordinateRegion { constructor(center, span) { this.center = center; this.span = span; } }
  class Padding { constructor(...a) { this.v = a; } }
  class MarkerAnnotation {
    constructor(coordinate, opts) { this.coordinate = coordinate; Object.assign(this, opts); }
  }
  class MapStub {
    constructor(el, opts) { this.el = el; Object.assign(this, opts); this.annotations = []; this.handlers = {}; state.map = this; }
    addAnnotation(a) { this.annotations.push(a); state.annotations = this.annotations; }
    addAnnotations(list) { this.annotations.push(...list); state.added = (state.added || 0) + list.length; state.annotations = this.annotations; }
    removeAnnotations(list) { this.annotations = this.annotations.filter((a) => !list.includes(a)); state.removed = (state.removed || 0) + list.length; state.annotations = this.annotations; }
    showItems() { state.fits++; }
    addEventListener(name, fn) { this.handlers[name] = fn; }
  }
  MapStub.ColorSchemes = { Dark: "dark", Light: "light" };

  const respond = (key, cb) => {
    state.calls.push(key);
    const run = () => {
      const list = state.places[key];
      if (list === "error") cb(new Error("fail"));
      else cb(null, { places: (list || []).map((p) => ({ ...p, coordinate: new Coordinate(p.lat, p.lon) })) });
    };
    const ms = state.delay[key] ?? state.delay["*"] ?? 0;
    setTimeout(run, ms);
  };
  class Search {
    constructor(opts) { this.opts = opts; }
    search(query, cb) { respond(query, cb); }
  }
  class PointsOfInterestSearch {
    constructor(opts) { this.opts = opts; }
    search(cb) { respond("__poi", cb); }
  }
  class Directions {
    route(req, cb) {
      state.calls.push("__directions");
      const secs = state.travelSeconds ?? 600;
      setTimeout(() => cb(null, { routes: [{ expectedTravelTime: secs }] }), 0);
    }
  }
  Directions.Transport = { Automobile: "Automobile" };

  window.mapkit = {
    init() {}, addEventListener() {},
    Coordinate, CoordinateSpan, CoordinateRegion, Padding, MarkerAnnotation, Map: MapStub,
    Search, PointsOfInterestSearch, Directions,
    PointOfInterestFilter: { including: (c) => ({ c }) },
    PointOfInterestCategory: { Restaurant: "Restaurant", Cafe: "Cafe", Bakery: "Bakery", Brewery: "Brewery", Winery: "Winery" },
    FeatureVisibility: { Hidden: "hidden" },
  };
  state.loaded = (state.loaded || 0) + 1;
  const me = document.currentScript || [...document.scripts].find((s) => (s.src || "").includes("mapkit"));
  const cbName = me && me.dataset.callback;
  if (cbName) setTimeout(() => window[cbName](), 0);
})();
