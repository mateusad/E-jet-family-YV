# AOP p2165+

var MSG_WARNING = 4;
var MSG_CAUTION = 3;
var MSG_ADVISORY = 2;
var MSG_STATUS = 1;
var MSG_MAINTENANCE = 0;

var messageCounts = [ 0, 0, 0, 0, 0 ];

# K-codes: these represent flight phases, used for CAS message inhibition.
# KNone is not a real K-code, it just exists so that we have a placeholder
# value to use when the inhibition system hasn't been initialized yet.
var KNone = 0;
var K1 = 1; # A/C parked
var K2a = 2; # A/C taxiing
var K2b = 3; # T/O roll
var K3 = 4; # Takeoff
var K4 = 5; # Climb/cruise/approach
var K5 = 6; # Landing

var signalProp = props.globals.getNode('/instrumentation/eicas/signals/messages-changed');
var blinkProp = props.globals.getNode('/instrumentation/eicas/blink-state');
var masterCautionProp = props.globals.getNode('/instrumentation/eicas/master/caution');
var masterWarningProp = props.globals.getNode('/instrumentation/eicas/master/warning');
var simTimeProp = props.globals.getNode('/sim/time/elapsed-sec');

var vec2boolmap = func (v) {
    var result = {};
    foreach (var k; v) {
        result[k] = 1;
    }
    return result;
};

var kCodeProp = props.globals.getNode('/instrumentation/eicas/k-code');
var kCodeSignalProps = {
        'takeoffPower': props.globals.getNode('/instrumentation/eicas/signals/takeoff-power'),
        'enginesRunning': props.globals.getNode('/instrumentation/eicas/signals/engines-running'),
        'rolling80knots': props.globals.getNode('/instrumentation/eicas/signals/above80knots'),
        'elec': props.globals.getNode('/instrumentation/eicas/signals/elec-power'),
        'below200ft': props.globals.getNode('/instrumentation/eicas/signals/below200ft'),
        'above400ft': props.globals.getNode('/instrumentation/eicas/signals/above400ft'),
        'below30kt': props.globals.getNode('/instrumentation/eicas/signals/below30kt'),
        'landed': props.globals.getNode('/instrumentation/eicas/signals/landed'),
    };

var checkKCode = func () {
    var currentKCode = kCodeProp.getValue();
    # printf("KCode before: %i", currentKCode);
    if (currentKCode == KNone) {
        if (kCodeSignalProps.elec.getBoolValue()) {
            currentKCode = K1;
            # printf("KNone -> K1");
        }
    }
    if (currentKCode == K1) {
        if (kCodeSignalProps.enginesRunning.getBoolValue()) {
            currentKCode = K2a;
            # printf("K1 -> K2a");
        }
    }
    if (currentKCode == K2a) {
        if (kCodeSignalProps.takeoffPower.getBoolValue()) {
            currentKCode = K2b;
            # printf("K2a -> K2b");
        }
    }
    if (currentKCode == K2b) {
        if (kCodeSignalProps.rolling80knots.getBoolValue()) {
            currentKCode = K3;
            # printf("K2b -> K3");
        }
    }
    if (currentKCode == K3) {
        if (kCodeSignalProps.above400ft.getBoolValue()) {
            currentKCode = K4;
            # printf("K3 -> K4");
        }
    }
    if (currentKCode == K4) {
        if (kCodeSignalProps.below200ft.getBoolValue()) {
            currentKCode = K5;
            # printf("K4 -> K5");
        }
    }
    if (currentKCode == K5) {
        if (kCodeSignalProps.landed.getBoolValue()) {
            currentKCode = KNone;
            # printf("K5 -> K1");
        }
    }
    if (currentKCode != KNone) {
        if (!kCodeSignalProps.elec.getBoolValue()) {
            currentKCode = KNone;
            # printf("-> KNone");
        }
    }
    # printf("KCode after: %i", currentKCode);
    kCodeProp.setValue(currentKCode);
};

var raiseSignal = func () { signalProp.setValue(1); }

var messages = [];

var compare = func (a, b) {
    if (a == b) return 0;
    if (a < b) return -1;
    if (a > b) return 1;
    die("OH TEH NOES");
};

var compareMessages = func (a, b) {
    return compare(b.level, a.level)
        or compare(b.priority, a.priority)
        or compare(a.timestamp, a.timestamp)
        or cmp(a.text, b.text);
};

var sortMessages = func () {
    messages = sort(messages, compareMessages);
};

var setMessage = func (level, text, priority, rootEicas=0) {
    var blink = 0;
    if (level == MSG_ADVISORY) {
        blink = 11; # blink for ~5 seconds
    }
    else if (level > MSG_ADVISORY) {
        blink = 864000; # I can keep doing this all day long
    }
    if (level == MSG_WARNING) {
        masterWarningProp.setBoolValue(1);
    }
    if (level == MSG_CAUTION) {
        masterCautionProp.setBoolValue(1);
    }
    var msg = {
            level: level,
            text: text,
            priority: priority,
            blink: blink,
            timestamp: simTimeProp.getValue() or 0,
            rootEicas: rootEicas,
        };
    append(messages, msg);
    messageCounts[msg.level] += 1;
    sortMessages();
    raiseSignal();
};

var clearMessage = func (level, text, priority) {
    var newMessages = [];
    var blinking = { MSG_WARNING: 0, MSG_CAUTION: 0 };
    messageCounts = [0, 0, 0, 0, 0];
    foreach (var msg; messages) {
        if (msg.text != text or msg.level != level) {
            append(newMessages, msg);
            messageCounts[msg.level] += 1;
            if (msg.blink) {
                blinking[msg.level] = 1;
            }
        }
    }
    if (!blinking[MSG_WARNING]) {
        masterWarningProp.setBoolValue(0);
    }
    if (!blinking[MSG_CAUTION]) {
        masterCautionProp.setBoolValue(0);
    }
    messages = newMessages;
    raiseSignal();
};

var clearBlinks = func (level) {
    foreach (var msg; messages) {
        if (msg.level == level) {
            msg.blink = 0;
        }
    }
};

var countdownBlinks = func (level) {
    foreach (var msg; messages) {
        if (msg.level == level and msg.blink > 0) {
            msg.blink = msg.blink - 1;
        }
    }
};

setlistener("sim/signals/fdm-initialized", func {
    blinkTimer = maketimer(0.5, func { blinkProp.toggleBoolValue(); });
    blinkTimer.simulatedTime = 1;
    blinkTimer.start();
    setlistener(blinkProp, func {
        countdownBlinks(MSG_ADVISORY);
    });
    setlistener(masterWarningProp, func (node) {
        if (!node.getBoolValue()) {
            clearBlinks(MSG_WARNING);
        }
    });
    setlistener(masterCautionProp, func (node) {
        if (!node.getBoolValue()) {
            clearBlinks(MSG_CAUTION);
        }
    });

    foreach (var k; keys(kCodeSignalProps)) {
        setlistener(kCodeSignalProps[k], checkKCode);
    }

    var listenOnProp = func (prop, cond, level, text, priority, rootEicas=0, inhibit=nil) {
        if (typeof(prop) == 'scalar') {
            var path = prop;
            prop = props.globals.getNode(prop);
            if (prop == nil)
                printf("Property not found: %s", path);
        }
        if (typeof(inhibit) == 'vector')
            inhibit = vec2boolmap(inhibit);

        var listener = nil;

        setlistener(kCodeProp, func (node) {
            var inhibited = 0;
            var k = kCodeProp.getValue();
            if (k == KNone or (inhibit != nil and inhibit[k])) {
                inhibited = 1;
            }
            if (inhibited) {
                clearMessage(level, text, priority);
                if (listener != nil) {
                    # printf("INHIBIT %s", text);
                    removelistener(listener);
                    listener = nil;
                }
            }
            else {
                if (listener == nil) {
                    # printf("ENABLE %s", text);
                    listener = setlistener(prop, func (node) {
                        if (cond(node.getValue())) {
                            # printf("SET %s", text);
                            setMessage(level, text, priority, rootEicas);
                        }
                        else {
                            # printf("CLEAR %s", text);
                            clearMessage(level, text, priority);
                        }
                    }, 1, 0);
                }
            }
        }, 1, 0);
    };

    var yes = func (val) { return !!val; }
    var no = func (val) { return !val; }

    listenOnProp("/instrumentation/eicas/messages/no-takeoff/master", yes, MSG_WARNING, 'NO TAKEOFF CONFIG', 0, 0, [K3, K4, K5]);
    listenOnProp("/instrumentation/eicas/messages/no-takeoff/ok", yes, MSG_STATUS, 'TAKEOFF OK', 0, 0, [K3, K4, K5]);
    listenOnProp("/engines/engine[0]/running", no, MSG_CAUTION, 'ENG 1 FAIL', 0, 0, [K3]);
    listenOnProp("/engines/engine[1]/running", no, MSG_CAUTION, 'ENG 2 FAIL', 0, 0, [K3]);
    listenOnProp("/gear/brake-overheat", yes, MSG_CAUTION, 'BRK OVERHEAT', 0, 0, [K3]);
    listenOnProp("/instrumentation/eicas/messages/parking-brake", yes, MSG_CAUTION, 'PRK BRK NOT REL', 0);
    listenOnProp("/instrumentation/eicas/messages/xpdr-stby", yes, MSG_CAUTION, 'XPDR 1 IN STBY', 0, 0, [K1, K2a, K2b, K3, K5]);
    listenOnProp("/instrumentation/eicas/messages/fuel-imbalance", yes, MSG_CAUTION, 'FUEL IMBALANCE', 0, 0, [K3, K5]);
    listenOnProp("/instrumentation/eicas/messages/fuel-low-left", yes, MSG_WARNING, 'FUEL 1 LO LEVEL', 10, 0, [K1, K2a, K2b, K3, K5]);
    listenOnProp("/instrumentation/eicas/messages/fuel-low-right", yes, MSG_WARNING, 'FUEL 2 LO LEVEL', 10, 0, [K1, K2a, K2b, K3, K5]);
    listenOnProp("/instrumentation/eicas/messages/fuel-equal-xfeed-open", yes, MSG_CAUTION, 'FUEL EQUAL - XFEED OPEN', 0, 0, [K3, K5]);
    listenOnProp("/instrumentation/eicas/messages/doors/l1/open", yes, MSG_WARNING, 'DOOR PAX FWD OPEN', 0, 0, [K3, K5]);
    listenOnProp("/instrumentation/eicas/messages/doors/l2/open", yes, MSG_WARNING, 'DOOR PAX AFT OPEN', 0, 0, [K3, K5]);
    listenOnProp("/instrumentation/eicas/messages/doors/r1/open", yes, MSG_WARNING, 'DOOR SERV FWD OPEN', 0, 0, [K3, K5]);
    listenOnProp("/instrumentation/eicas/messages/doors/r2/open", yes, MSG_WARNING, 'DOOR SERV AFT OPEN', 0, 0, [K3, K5]);
    listenOnProp("/instrumentation/eicas/messages/electrical/emergency", yes, MSG_WARNING, 'ELEC EMERGENCY', 0, 1);
    listenOnProp("/instrumentation/eicas/messages/electrical/batteries-off", yes, MSG_WARNING, 'BATT 1-2 OFF', 0);
    listenOnProp("/instrumentation/eicas/messages/iru-excessive-motion", yes, MSG_CAUTION, 'IRS EXCESSIVE MOTION', 0, 0, [K2b, K3, K4, K5]);
    listenOnProp("/systems/electrical/sources/battery[0]/status", no, MSG_CAUTION, 'BATT 1 OFF', 0, 0, [K3, K5]);
    listenOnProp("/systems/electrical/sources/battery[1]/status", no, MSG_CAUTION, 'BATT 2 OFF', 0, 0, [K3, K5]);
    listenOnProp("/instrumentation/eicas/messages/electrical/external-power-connected", yes, MSG_CAUTION, 'GPU CONNECTED', 0, 0, [K3, K4, K5]);
    listenOnProp("/instrumentation/eicas/messages/electrical/idg1", yes, MSG_CAUTION, 'IDG 1 OFF', 0, 0, [K3, K5]);
    listenOnProp("/instrumentation/eicas/messages/electrical/idg2", yes, MSG_CAUTION, 'IDG 2 OFF', 0, 0, [K3, K5]);
    listenOnProp("/systems/electrical/buses/ac[1]/powered", no, MSG_CAUTION, 'AC BUS 1 OFF', 0, 1, [K3, K5]);
    listenOnProp("/systems/electrical/buses/ac[2]/powered", no, MSG_CAUTION, 'AC BUS 2 OFF', 0, 1, [K3, K5]);
    listenOnProp("/systems/electrical/buses/ac[3]/powered", no, MSG_CAUTION, 'AC ESS BUS OFF', 0, 1, [K3, K5]);
    listenOnProp("/systems/electrical/buses/ac[4]/powered", no, MSG_CAUTION, 'AC STBY BUS OFF', 0, 0, [K3, K5]);
    listenOnProp("/systems/electrical/buses/dc[1]/powered", no, MSG_CAUTION, 'DC BUS 1 OFF', 0, 1, [K3, K5]);
    listenOnProp("/systems/electrical/buses/dc[2]/powered", no, MSG_CAUTION, 'DC BUS 2 OFF', 0, 1, [K3, K5]);
    listenOnProp("/systems/electrical/buses/dc[3]/powered", no, MSG_CAUTION, 'DC ESS BUS 1 OFF', 0, 1, [K3, K5]);
    listenOnProp("/systems/electrical/buses/dc[4]/powered", no, MSG_CAUTION, 'DC ESS BUS 2 OFF', 0, 1, [K3, K5]);
    listenOnProp("/systems/electrical/buses/dc[5]/powered", no, MSG_CAUTION, 'DC ESS BUS 3 OFF', 0, 1, [K3, K5]);
    listenOnProp("/instrumentation/iru[0]/outputs/valid-att", no, MSG_CAUTION, 'IRS 1 FAIL', 1);
    listenOnProp("/instrumentation/iru[1]/outputs/valid-att", no, MSG_CAUTION, 'IRS 2 FAIL', 1);
    listenOnProp("/instrumentation/iru[0]/outputs/valid", no, MSG_ADVISORY, 'IRS 1 NAV MODE FAIL', 1, 0, [K1, K2a, K2b, K3, K5]);
    listenOnProp("/instrumentation/iru[1]/outputs/valid", no, MSG_ADVISORY, 'IRS 2 NAV MODE FAIL', 1, 0, [K1, K2a, K2b, K3, K5]);
    listenOnProp("/instrumentation/iru[0]/signals/aligning", yes, MSG_ADVISORY, 'IRS 1 ALIGNING', 0, 0, [K2b, K3, K5]);
    listenOnProp("/instrumentation/iru[1]/signals/aligning", yes, MSG_ADVISORY, 'IRS 2 ALIGNING', 0, 0, [K2b, K3, K5]);
    listenOnProp("/instrumentation/iru[0]/reference/valid", no, MSG_ADVISORY, 'IRS 1 PRES POS INVALID', 0, 0, [K2a, K2b, K3, K5]);
    listenOnProp("/instrumentation/iru[1]/reference/valid", no, MSG_ADVISORY, 'IRS 2 PRES POS INVALID', 0, 0, [K2a, K2b, K3, K5]);
    listenOnProp("fdm/jsbsim/fcs/yaw-damper-enable", no, MSG_ADVISORY, 'YD OFF', 0);
    listenOnProp("fdm/jsbsim/gear/unit[0]/castered", yes, MSG_ADVISORY, 'STEER OFF', 0, 0, [K3, K4]);
    listenOnProp("/instrumentation/eicas/messages/apu/shutdown", yes, MSG_STATUS, 'APU SHUTTING DOWN', 0, 0, [K2b, K3, K5]);
    listenOnProp("/controls/flight/steep-approach", yes, MSG_STATUS, 'STEEP APPR', 0);
    listenOnProp("/cpdlc/unread", yes, MSG_STATUS, 'ATC UPLINK', 0, 0, [K3, K5]);
    listenOnProp("/acars/telex/unread", yes, MSG_STATUS, 'ACARS MSG', 0, 0, [K3, K5]);

    listenOnProp("/systems/pressurization/signals/cabin-ft-warning", yes, MSG_WARNING, 'CABIN ALTITUDE HIGH', 0, 0, [K1, K2a, K2b, K3, K5]);
    listenOnProp("/systems/pressurization/signals/diff-psi-warning", yes, MSG_CAUTION, 'CABIN DIFF PRESS FAIL', 0, 0, [K2b, K3, K5]);
    listenOnProp("/instrumentation/eicas/signals/bleed-fail[0]", yes, MSG_CAUTION, 'BLEED 1 FAIL', 0, 0, [K2b, K3, K5]);
    listenOnProp("/instrumentation/eicas/signals/bleed-fail[1]", yes, MSG_CAUTION, 'BLEED 2 FAIL', 0, 0, [K2b, K3, K5]);
    listenOnProp("/controls/pneumatic/engine-bleed[0]", no, MSG_ADVISORY, 'BLEED 1 OFF', 0, 0, [K2b, K3, K5]);
    listenOnProp("/controls/pneumatic/engine-bleed[1]", no, MSG_ADVISORY, 'BLEED 2 OFF', 0, 0, [K2b, K3, K5]);
    listenOnProp("/instrumentation/eicas/signals/pack-off[0]", yes, MSG_ADVISORY, 'PACK 1 OFF', 0, 0, [K2b, K3, K5]);
    listenOnProp("/instrumentation/eicas/signals/pack-off[1]", yes, MSG_ADVISORY, 'PACK 2 OFF', 0, 0, [K2b, K3, K5]);
    listenOnProp("/controls/pneumatic/xbleed", no, MSG_ADVISORY, 'XBLEED SW OFF', 0, 0, [K2b, K3, K5]);
    listenOnProp("/systems/pneumatic/valves/apu", yes, MSG_STATUS, 'BLEED APU VLV OPEN', 0, 0, [K2b, K3, K5]);

    listenOnProp("/systems/hydraulic/system[0]/pressurized", no, MSG_CAUTION, 'HYD 1 LO PRESS', 0, 0, [K3]);
    listenOnProp("/systems/hydraulic/system[1]/pressurized", no, MSG_CAUTION, 'HYD 2 LO PRESS', 0, 0, [K3]);
    listenOnProp("/systems/hydraulic/system[2]/pressurized", no, MSG_CAUTION, 'HYD 3 LO PRESS', 0, 0, [K3]);

    listenOnProp("/controls/hydraulic/ehp[2]", no, MSG_ADVISORY, 'HYD 3 PUMP A NOT ON', 0, 0, [K1, K3, K5]);
    listenOnProp("/controls/hydraulic/ptu", yes, MSG_ADVISORY, 'HYD PTU NOT AUTO', 0, 0, [K3, K5]);
    listenOnProp("/controls/hydraulic/ehp[0]", yes, MSG_ADVISORY, 'HYD1 PUMP NOT AUTO', 0, 0, [K3, K5]);
    listenOnProp("/controls/hydraulic/ehp[1]", yes, MSG_ADVISORY, 'HYD2 PUMP NOT AUTO', 0, 0, [K3, K5]);
    listenOnProp("/controls/hydraulic/ehp[3]", yes, MSG_ADVISORY, 'HYD3 PUMP B NOT AUTO', 0, 0, [K3, K5]);

    listenOnProp("/instrumentation/eicas/messages/debug", yes, MSG_WARNING, 'DEBUG WARN 1', 0);
    listenOnProp("/instrumentation/eicas/messages/debug", yes, MSG_WARNING, 'DEBUG WARN 2', 0);
    listenOnProp("/instrumentation/eicas/messages/debug", yes, MSG_WARNING, 'DEBUG WARN 3', 0);
    listenOnProp("/instrumentation/eicas/messages/debug", yes, MSG_WARNING, 'DEBUG WARN 4', 0);
    listenOnProp("/instrumentation/eicas/messages/debug", yes, MSG_WARNING, 'DEBUG WARN 5', 0);
    listenOnProp("/instrumentation/eicas/messages/debug", yes, MSG_CAUTION, 'DEBUG CAUTION 1', 0);
    listenOnProp("/instrumentation/eicas/messages/debug", yes, MSG_CAUTION, 'DEBUG CAUTION 2', 0);
    listenOnProp("/instrumentation/eicas/messages/debug", yes, MSG_CAUTION, 'DEBUG CAUTION 3', 0);
    listenOnProp("/instrumentation/eicas/messages/debug", yes, MSG_CAUTION, 'DEBUG CAUTION 4', 0);
    listenOnProp("/instrumentation/eicas/messages/debug", yes, MSG_CAUTION, 'DEBUG CAUTION 5', 0);
    listenOnProp("/instrumentation/eicas/messages/debug", yes, MSG_CAUTION, 'DEBUG CAUTION 6', 0);
    listenOnProp("/instrumentation/eicas/messages/debug", yes, MSG_CAUTION, 'DEBUG CAUTION 7', 0);
    listenOnProp("/instrumentation/eicas/messages/debug", yes, MSG_CAUTION, 'DEBUG CAUTION 8', 0);
    listenOnProp("/instrumentation/eicas/messages/debug", yes, MSG_CAUTION, 'DEBUG CAUTION 9', 0);
    listenOnProp("/instrumentation/eicas/messages/debug", yes, MSG_CAUTION, 'DEBUG CAUTION 10', 0);
    listenOnProp("/instrumentation/eicas/messages/debug", yes, MSG_CAUTION, 'DEBUG CAUTION 11', 0);
    listenOnProp("/instrumentation/eicas/messages/debug", yes, MSG_CAUTION, 'DEBUG CAUTION 12', 0);
    listenOnProp("/instrumentation/eicas/messages/debug", yes, MSG_CAUTION, 'DEBUG CAUTION 13', 0);
    listenOnProp("/instrumentation/eicas/messages/debug", yes, MSG_CAUTION, 'DEBUG CAUTION 14', 0);
    listenOnProp("/instrumentation/eicas/messages/debug", yes, MSG_CAUTION, 'DEBUG CAUTION 15', 0);
    listenOnProp("/instrumentation/eicas/messages/debug", yes, MSG_CAUTION, 'DEBUG CAUTION 16', 0);
    listenOnProp("/instrumentation/eicas/messages/debug", yes, MSG_ADVISORY, 'DEBUG ADVISORY 1', 0);
    listenOnProp("/instrumentation/eicas/messages/debug", yes, MSG_ADVISORY, 'DEBUG ADVISORY 2', 0);
    listenOnProp("/instrumentation/eicas/messages/debug", yes, MSG_ADVISORY, 'DEBUG ADVISORY 3', 0);
    listenOnProp("/instrumentation/eicas/messages/debug", yes, MSG_ADVISORY, 'DEBUG ADVISORY 4', 0);
    listenOnProp("/instrumentation/eicas/messages/debug", yes, MSG_ADVISORY, 'DEBUG ADVISORY 5', 0);
    listenOnProp("/instrumentation/eicas/messages/debug", yes, MSG_ADVISORY, 'DEBUG ADVISORY 6', 0);
    listenOnProp("/instrumentation/eicas/messages/debug", yes, MSG_ADVISORY, 'DEBUG ADVISORY 7', 0);
    listenOnProp("/instrumentation/eicas/messages/debug", yes, MSG_ADVISORY, 'DEBUG ADVISORY 8', 0);
    listenOnProp("/instrumentation/eicas/messages/debug", yes, MSG_ADVISORY, 'DEBUG ADVISORY 9', 0);
    listenOnProp("/instrumentation/eicas/messages/debug", yes, MSG_ADVISORY, 'DEBUG ADVISORY 10', 0);
    listenOnProp("/instrumentation/eicas/messages/debug", yes, MSG_ADVISORY, 'DEBUG ADVISORY 11', 0);
    listenOnProp("/instrumentation/eicas/messages/debug", yes, MSG_ADVISORY, 'DEBUG ADVISORY 12', 0);
    listenOnProp("/instrumentation/eicas/messages/debug", yes, MSG_ADVISORY, 'DEBUG ADVISORY 13', 0);
    listenOnProp("/instrumentation/eicas/messages/debug", yes, MSG_ADVISORY, 'DEBUG ADVISORY 14', 0);
    listenOnProp("/instrumentation/eicas/messages/debug", yes, MSG_ADVISORY, 'DEBUG ADVISORY 15', 0);
    listenOnProp("/instrumentation/eicas/messages/debug", yes, MSG_ADVISORY, 'DEBUG ADVISORY 16', 0);
    listenOnProp("/instrumentation/eicas/messages/debug", yes, MSG_STATUS, 'DEBUG STATUS 1', 0);
    listenOnProp("/instrumentation/eicas/messages/debug", yes, MSG_STATUS, 'DEBUG STATUS 2', 0);
    listenOnProp("/instrumentation/eicas/messages/debug", yes, MSG_STATUS, 'DEBUG STATUS 3', 0);
    listenOnProp("/instrumentation/eicas/messages/debug", yes, MSG_STATUS, 'DEBUG STATUS 4', 0);
    listenOnProp("/instrumentation/eicas/messages/debug", yes, MSG_STATUS, 'DEBUG STATUS 5', 0);
    listenOnProp("/instrumentation/eicas/messages/debug", yes, MSG_STATUS, 'DEBUG STATUS 6', 0);
    listenOnProp("/instrumentation/eicas/messages/debug", yes, MSG_STATUS, 'DEBUG STATUS 7', 0);
    listenOnProp("/instrumentation/eicas/messages/debug", yes, MSG_STATUS, 'DEBUG STATUS 8', 0);
    listenOnProp("/instrumentation/eicas/messages/debug", yes, MSG_STATUS, 'DEBUG STATUS 9', 0);
    listenOnProp("/instrumentation/eicas/messages/debug", yes, MSG_STATUS, 'DEBUG STATUS 10', 0);
    listenOnProp("/instrumentation/eicas/messages/debug", yes, MSG_STATUS, 'DEBUG STATUS 11', 0);
    listenOnProp("/instrumentation/eicas/messages/debug", yes, MSG_STATUS, 'DEBUG STATUS 12', 0);
    listenOnProp("/instrumentation/eicas/messages/debug", yes, MSG_STATUS, 'DEBUG STATUS 13', 0);
    listenOnProp("/instrumentation/eicas/messages/debug", yes, MSG_STATUS, 'DEBUG STATUS 14', 0);
    listenOnProp("/instrumentation/eicas/messages/debug", yes, MSG_STATUS, 'DEBUG STATUS 15', 0);
    listenOnProp("/instrumentation/eicas/messages/debug", yes, MSG_STATUS, 'DEBUG STATUS 16', 0);
});
