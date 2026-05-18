// vpnc-script-win.js for openconnect FortiGate (Windows Script Host / JScript)
var sh = new ActiveXObject("WScript.Shell");
function run(cmd) { return sh.Run("cmd.exe /c " + cmd, 0, true); }

var env = sh.Environment("Process");
var reason = env("reason");
var ip = env("INTERNAL_IP4_ADDRESS");
var mtu = env("INTERNAL_IP4_MTU") || "1400";
var count = parseInt(env("CISCO_SPLIT_INC") || "0");
var tunIdx = env("TUNIDX");
var tunDev = env("TUNDEV");

if (reason == "connect") {
    // Configure IP on the wintun adapter
    if (ip && tunDev) {
        // Set static IP on the adapter
        run("netsh interface ip set address name=\"" + tunDev + "\" source=static addr=" + ip + " mask=255.255.255.255");
        // Set MTU
        run("netsh interface ip set subinterface \"" + tunDev + "\" mtu=" + mtu + " store=active");
        // Wait a moment for IP to settle
        var t = new Date().getTime() + 2000;
        while (new Date().getTime() < t) {};
    }
    // Add split routes through the wintun interface
    for (var i = 0; i < count; i++) {
        var addr = env("CISCO_SPLIT_INC_" + i + "_ADDR");
        var mask = env("CISCO_SPLIT_INC_" + i + "_MASK");
        if (addr && mask && ip && tunIdx) {
            run("route ADD " + addr + " MASK " + mask + " " + ip + " IF " + tunIdx);
        }
    }
} else if (reason == "disconnect") {
    for (var i = 0; i < count; i++) {
        var addr = env("CISCO_SPLIT_INC_" + i + "_ADDR");
        if (addr) { run("route DELETE " + addr); }
    }
}

WScript.Quit(0);
