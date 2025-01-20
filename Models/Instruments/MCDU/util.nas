# Various utility cruft for MCDU programming

var map = func (f, input) {
    var output = [];
    foreach (var x; input) {
        append(output, f(x));
    }
    return output;
};

var utf8NumBytes = func (c) {
    if ((c & 0x80) == 0x00) { return 1; }
    if ((c & 0xE0) == 0xC0) { return 2; }
    if ((c & 0xF0) == 0xE0) { return 3; }
    if ((c & 0xF8) == 0xF0) { return 4; }
    printf("UTF8 error (%d / %02x)", c, c);
    return 1;
};

var parseOctal = func (s) {
    var val = 0;
    for (var i = 0; i < size(s); i += 1) {
        val = val * 8;
        var c = s[i];
        if (c < 48 or c > 55) {
            return nil;
        }
        val += c - 48;
    }
    return val;
};

var vecfind = func (needle, haystack) {
    forindex (var i; haystack) {
        if (haystack[i] == needle) {
            return i;
        }
    }
    return -1;
};

var swapProps = func (prop1, prop2) {
    fgcommand("property-swap", {
        "property[0]": prop1,
        "property[1]": prop2
    });
};

var prepended = func (val, vec) {
    var result = [val];
    foreach (var v; vec) {
        append(result, v);
    }
    return result;
};


var formatRestrictions = func (wp, transitionAlt = 18000, pretty = 0) {
    var formattedAltRestr = pretty ? "-----" : "-";
    if (wp.alt_cstr != nil and wp.alt_cstr_type != nil and wp.alt_cstr_type != 'delete') {
        if (wp.alt_cstr > transitionAlt) {
            formattedAltRestr = sprintf("FL%03.0f", wp.alt_cstr / 100);
        }
        else {
            formattedAltRestr = sprintf(pretty ? "%5.0f" : "%1.0f", wp.alt_cstr);
        }
        if (wp.alt_cstr_type == "above") {
            formattedAltRestr ~= "A";
        }
        else if (wp.alt_cstr_type == "below") {
            formattedAltRestr ~= "B";
        }
    }
    var formattedSpeedRestr = pretty ? "---" : "-";
    if (wp.speed_cstr != nil and wp.speed_cstr_type != nil and wp.speed_cstr_type != 'delete') {
        if (wp.speed_cstr_type == "mach") {
            formattedSpeedRestr = sprintf("%0.2fM", wp.speed_cstr);
        }
        else {
            formattedSpeedRestr = sprintf(pretty ? "%3.0f" : "%1.0f", wp.speed_cstr);
        }
        if (wp.speed_cstr_type == "above") {
            formattedSpeedRestr ~= "A";
        }
        else if (wp.speed_cstr_type == "below") {
            formattedSpeedRestr ~= "B";
        }
    }
    return sprintf(pretty ? "%4s/%-4s" : "%s/%s", formattedSpeedRestr, formattedAltRestr);
};

var extractAboveBelow = func (str) {
    # debug.dump("extractAboveBelow", str);
    if (str == '') {
        return [str, nil];
    }
    if (num(str) != nil) {
        return [str, nil];
    }
    var last = substr(str, -1, 1);
    if (num(last) == nil) {
        var corePart = substr(str, 0, size(str) - 1);
        return [corePart, last];
    }
    else {
        return [str, nil];
    }
};

var parseAsAltitude = func (str) {
    var n = num(str);
    if (n == nil) {
        if (substr(str, 0, 2) == "FL") {
            n = substr(str, 2);
            if (n == nil) {
                return nil;
            }
            else {
                return n * 100;
            }
        }
        else {
            return nil;
        }
    }
    else {
        if (n >= 1000) {
            return n;
        }
        else {
            return nil;
        }
    }
};

var parseAsSpeed = func (str) {
    # debug.dump("parseAsSpeed", str);
    var n = num(str);
    if (n != nil and n < 1000) {
        return n;
    }
    else {
        return nil;
    }
};

var parseAsMach = func (str) {
    # debug.dump("parseAsMach", str);
    var n = num(str);
    if (n == nil) return nil;

    if (n < 1.0) {
        return n;
    }
    else if (n < 10.0) {
        return n / 10.0;
    }
    else if (n < 100.0) {
        return n / 100.0;
    }
};

var parseRestrictions = func (str) {
    var s = split("/", str);
    # debug.dump("Split restrictions", s);
    if (size(s) == 0) { return nil; }
    var speedPart = nil;
    var altPart = nil;
    if (size(s) == 1) {
        # extract above/below marker
        var parts = extractAboveBelow(s[0]);
        if (parts == nil) { return nil; }
        
        # if the indicator is "M", then we're dealing with an "at mach" rule.
        if (parts[1] == "M") {
            var mach = parseAsMach(parts[0]);
            if (mach == nil) { return nil; }
            return {
                speed: {
                    val: mach,
                    ty: 'mach',
                },
                alt: nil,
            }
        }
        else {
            var ty = 'at';
            if (parts[1] == "A") { ty = 'above'; }
            if (parts[1] == "B") { ty = 'below'; }
            var alt = parseAsAltitude(parts[0]);
            var speed = parseAsSpeed(parts[0]);
            if (alt != nil) {
                return {
                    speed: nil,
                    alt: {
                        val: alt,
                        ty: ty,
                    },
                };
            }
            else {
                return {
                    speed: {
                        val: speed,
                        ty: ty,
                    },
                    alt: nil,
                }
            }
        }
    } # size = 1
    else {
        var speedPart = s[0];
        var altPart = s[1];
        var result = { speed: nil, alt: nil };

        var speedParts = extractAboveBelow(speedPart);
        if (speedParts[1] == "M") {
            var mach = parseAsMach(speedParts[0]);
            if (mach != nil) {
                result.speed = { val: mach, ty: 'mach' };
            }
        }
        else {
            var speed = nil;
            if (substr(speedPart, 0, 1) == "-") {
                result.speed = { val: nil, ty: '' };
            }
            else {
                speed = parseAsSpeed(speedParts[0]);
                if (speed != nil) {
                    result.speed = { val: speed, ty: 'at' };
                    if (speedParts[1] == "A") { result.speed.ty = 'above'; }
                    if (speedParts[1] == "B") { result.speed.ty = 'below'; }
                }
            }
        }

        var altParts = extractAboveBelow(altPart);
        var alt = nil;
        if (substr(altPart, 0, 1) == "-") {
            result.alt = { val: nil, ty: '' };
        }
        else {
            alt = parseAsAltitude(altParts[0]);
            if (alt != nil) {
                result.alt = { val: alt, ty: 'at' };
                if (altParts[1] == "A") { result.alt.ty = 'above'; }
                if (altParts[1] == "B") { result.alt.ty = 'below'; }
            }
        }

        return result;
    }
};

var celsiusToFahrenheit = func (c) {
    return 32.0 + c * 1.8;
};

var parseArinc424Latlon = func(str) {
    var parsed = [];
    var success = 0;
    var quadrant = nil;
    var lat = 0;
    var lon = 0;

    if (string.match(str, "[0-9][0-9][NSWE][0-9][0-9]")) {
        success = string.scanf(str, "%2d%1s%2d", parsed);
        if (success > 0) {
            lat = parsed[0];
            lon = parsed[2] + 100;
            quadrant = parsed[1];
        }
    }
    elsif (string.match(str, "[0-9][0-9][0-9][0-9][NSWE]")) {
        success = string.scanf(str, "%2d%2d%1s", parsed);
        if (success > 0) {
            lat = parsed[0];
            lon = parsed[1];
            quadrant = parsed[2];
        }
    }
    elsif (string.match(str, "H[0-9][0-9][0-9][0-9]")) {
        success = string.scanf(str, "H%2d%2d", parsed);
        if (success > 0) {
            lat = parsed[0] + 0.5;
            lon = parsed[1];
            quadrant = "N";
        }
    }

    if (quadrant == nil) return nil;

    if (quadrant == 'N') {
        lat = -lat;
        lon = -lon;
    }
    elsif (quadrant == 'S') {
    }
    elsif (quadrant == 'W') {
        lon = -lon;
    }
    elsif (quadrant == 'E') {
        lat = -lat;
    }
    else {
            return nil;
    }
    return {"lat": lat, "lon": lon};
};

# foreach (var str; ["50N60", "5060N", "H5060", "5060E", "50E60", "5060S", "50S60", "5060W", "50W60"]) {
#     debug.dump(str, parseArinc424Latlon(str));
# }

var parseMCDULatlon = func(strDegMins, strFrac = '0') {
    strDegMins = strDegMins ~ '';
    var mins = num(substr(strDegMins, size(strDegMins), 2) ~ '.' ~ strFrac);
    var degs = num(substr(strDegMins, 0, size(strDegMins) - 2));
    if (mins == nil or degs == nil) {
        return nil;
    }
    return degs + mins / 60;
}

var parseWaypoint = func (ident, ref=nil, forceWP=1) {
    var parts = split('/', ident);
    if (size(parts) == 2) {
        # this could be a lat/lon pair
        var items = [];
        var result = string.scanf(ident, "%1s%4u.%1u/%1s%5u.%1u", items);
        if (result >= 1) {
            var latSign = (items[0] == 'N') ? 1 : 0;
            var lonSign = (items[3] == 'E') ? 1 : 0;
            var lat = parseMCDULatlon(items[1], items[2]);
            var lon = parseMCDULatlon(items[4], items[5]);
            var coords = geo.Coord.new();
            coords.set_latlon(lat, lon);
            return [ createWP(coords, ident) ];
        }
    }

    var refPoints = findWaypointsByID(parts[0], ref);
    if (forceWP)
        refPoints = map(createWPFrom, refPoints);
    if (size(parts) == 1) {
        # this is the only part, so just use the waypoint as-is
        return refPoints;
    }
    else if (size(parts) == 3) {
        # 3 parts: this is probably a P/B/D triplet (Point / Bearing / Distance)
        var bearing = num(parts[1]);
        var distance = num(parts[2]);
        if (bearing == nil or distance == nil) return nil;
        var f = func (positioned) {
            var coords = geo.Coord.new();
            coords.set_latlon(positioned.lat, positioned.lon);
            coords.apply_course_distance(bearing, distance);
            return createWP(coords, ident);
        };
        return map(f, refPoints);
    }
    return nil;
};


var formatETE = func(time_secs) {
    var corrected = math.mod(time_secs, 86400);
    var hours = math.floor(corrected / 3600);
    var minutes = math.mod(math.floor(corrected / 60), 60);
    return sprintf("%02.0fH%02.0f", hours, minutes);
};

var formatZulu = func (time_secs) {
    var corrected = math.mod(time_secs, 86400);
    var hours = math.floor(corrected / 3600);
    var minutes = math.mod(math.floor(corrected / 60), 60);
    return sprintf("%02.0f%02.0fz", hours, minutes);
};

var formatDist = func (dist) {
    if (dist == nil) return "----";
    if (dist >= 10000) return "++++";
    if (dist >= 100) return sprintf("%4.0f", dist);
    if (dist >= 0) return sprintf("%4.1f", dist);
    return "----";
};

var formatLat = func (lat) {
    return formatGeo(lat, 'lat');
};

var formatLon = func (lon) {
    return formatGeo(lon, 'lon');
};

var formatGeo = func (val, axis) {
    var fmt = '';
    var invalidFmt = '---';
    var dirs = ['', ''];

    if (axis == "LAT" or axis == 'lat' or axis == 0) {
        fmt = "%1s%02d°%04.1f";
        invalidFmt = "---°--.-";
        dirs = ["S", "N"];
    }
    elsif (axis == "LON" or axis == 'lon' or axis == 1) {
        fmt = "%1s%03d°%04.1f";
        invalidFmt = "----°--.-";
        dirs = ["W", "E"];
    }
    else {
        return '!!!';
    }
    if (val == nil or val == '' or typeof(val) != 'scalar') {
        return invalidFmt;
    }
    var dir = (val < 0) ? (dirs[0]) : (dirs[1]);
    var degs = math.abs(val);
    var mins = math.fmod(degs * 60, 60);

    return sprintf(fmt, dir, degs, mins);
};

var findWaypointsByID = func (ident, ref=nil) {
    if (ref == nil) { ref = geo.aircraft_position(); }

    if (size(ident) < 2) {
        # single letter = nonsensical
        return [];
    }
    else if (size(ident) <= 3) {
        # 2 = NDB
        # 3 = VOR/DME
        # ...but could also be a fix replacing a former navaid, such as LBE
        # near EDDH
        var v = findNavaidsByID(ref, ident, 'vor');
        var d = findNavaidsByID(ref, ident, 'dme');
        var n = findNavaidsByID(ref, ident, 'ndb');
        var f = findFixesByID(ref, ident);
        return dedupAndSort(v ~ d ~ n ~ f, ref);
    }
    else if (size(ident) == 4) {
        # 4 = airport
        return findAirportsByICAO(ident);
    }
    else if (size(ident) >= 5) {
        # 5 = a fix
        return findFixesByID(ref, ident);
    }
};

var dedupAndSort = func (points, ref=nil) {
    if (ref == nil) { ref = geo.aircraft_position(); }
    var resultSet = {};
    var rawResults = [];

    foreach (var wp; points) {
        var coords = geo.Coord.new();
        coords.set_latlon(wp.lat, wp.lon);
        var dist = M2NM * coords.distance_to(ref);
        var hash = md5(wp.id ~ wp.lat ~ wp.lon);
        if (!contains(resultSet, hash)) {
            resultSet[hash] = 1;
            append(rawResults, { wp: wp, dist: dist });
        }
    }
    var compare = func(a, b){
        if (a.dist < b.dist) {
            return -1;
        }
        elsif (a.dist == b.dist) {
            return 0;
        }
        else {
            return 1;
        }
    }
    rawResults = sort(rawResults, compare);
    return map(func (a) { return a.wp; }, rawResults);
};

var cpdlcDatalinkStatusName = func (status) {
    if (status == cpdlc.LOGON_NO_LINK) {
        return 'ATN FAIL';
    }
    else {
        return 'ATN READY';
    }
};

var orDashes = func (length, ralign=0) {
    return func (val) {
        if (val == nil or val == '')
            return substr('------------------------', 0, length);
        else
            return sprintf('%' ~ (ralign ? '' : '-') ~ length ~ "s", val);
    }
};

var orBoxes = func (length, ralign=0) {
    return func (val) {
        if (val == nil or val == '')
            return utf8.substr(hollow_squares, 0, length);
        else
            return sprintf('%' ~ (ralign ? '' : '-') ~ length ~ "s", val);
    }
};

var lineWrap = func (txt, maxLength, ellipse='..') {
    var lines = [];
    var line = '';

    var rawLines = split("\n", txt);
    var first = 1;

    foreach (var rawLine; rawLines) {
        first = 1;
        var words = split(' ', rawLine);
        foreach (var word; words) {
            if (utf8.size(line) + utf8.size(word) + (first ? 0 : 1) >= maxLength) {
                append(lines, line);
                line = '';
                first = 1;
            }
            if (first) {
                while (utf8.size(word) > maxLength) {
                    append(lines, utf8.substr(word, 0, maxLength - utf8.strlen(ellipse)) ~ ellipse);
                    word = utf8.substr(word, maxLength - utf8.strlen(ellipse));
                }
                line = word;
            }
            else {
                line = line ~ ' ' ~ word;
            }
            first = 0;
        }
        if (!first) {
            append(lines, line);
            line = '';
            first = 1;
        }
    }
    return lines;
};

