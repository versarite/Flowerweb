//
// FlowerWeb - app.js
//

document.addEventListener("DOMContentLoaded", initPage);

let firstStatus = true;      // fill inputs from the server only once
let timerSelectBusy = false; // don't overwrite the dropdown while in use

function initPage()
{
    const timerSelect = document.getElementById("timerHours");
    timerSelect.addEventListener("change", timerChanged);
    timerSelect.addEventListener("focus", () => timerSelectBusy = true);
    timerSelect.addEventListener("blur",  () => timerSelectBusy = false);

    updateTelemetry();
    setInterval(updateTelemetry, 5000);
}

function setText(id, text)
{
    const el = document.getElementById(id);
    if (el)
        el.innerText = text;
}

function setStatus(text, color)
{
    const status = document.getElementById("status");
    if (!status)
        return;
    status.innerText = text;
    status.style.color = color || "#aaa";
}

function formatRemaining(minutes)
{
    if (minutes < 1)
        return "less than a minute";
    const h = Math.floor(minutes / 60);
    const m = minutes % 60;
    if (h === 0)
        return m + " min";
    return h + " h " + m + " min";
}

// ------------------------------------------------------------
// Camera
// ------------------------------------------------------------

function initializeCamera(port, name)
{
    const frame = document.getElementById("cameraFeed");
    if (!frame)
        return;
    frame.src = "http://" + window.location.hostname + ":" + port + "/" + name;
}

// ------------------------------------------------------------
// Status polling
// ------------------------------------------------------------

function updateTelemetry()
{
    fetch("/api/status")
        .then(response => response.json())
        .then(data =>
        {
            setText("pi-ip", data.ip);
            setText("pi-temp", data.temp);

            if (firstStatus)
            {
                firstStatus = false;
                initializeCamera(data.cameraPort, data.cameraName);

                const pulse = document.getElementById("pulseTime");
                if (pulse)
                {
                    pulse.value = data.pulseTimeMS;
                    pulse.max = data.maxPulseTimeMS;
                }
            }

            const timer = document.getElementById("timerHours");
            if (timer && !timerSelectBusy)
                timer.value = String(data.timerInterval);

            if (data.timerInterval === 0)
                setText("timerStatus", "Timer off");
            else
                setText("timerStatus",
                        "Next watering in " + formatRemaining(data.minutesRemaining));

            const btn = document.getElementById("waterBtn");
            if (btn)
                btn.disabled = data.watering;

            if (data.watering)
                setStatus("Watering… " + data.wateringSecondsLeft + " s left", "#3498db");
            else if (document.getElementById("status").innerText.startsWith("Watering"))
                setStatus("System Ready");
        })
        .catch(err => console.error(err));
}

// ------------------------------------------------------------
// Manual watering
// ------------------------------------------------------------

function triggerRelay()
{
    const pulseTime = Number(document.getElementById("pulseTime").value);

    setStatus("Triggering relay...", "#f39c12");

    fetch("/api/trigger", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ pulseTimeMS: pulseTime })
    })
        .then(response => response.json())
        .then(data =>
        {
            if (data.status === "success")
            {
                document.getElementById("pulseTime").value = data.pulseTimeMS;
                setStatus("Watering…", "#3498db");
            }
            else
            {
                setStatus("Relay failed: " + (data.message || "unknown error"), "#e74c3c");
            }
            updateTelemetry();
        })
        .catch(error =>
        {
            console.error(error);
            setStatus("Communication error", "#e74c3c");
        });
}

// ------------------------------------------------------------
// Reboot
// ------------------------------------------------------------

function rebootPi()
{
    if (!confirm("Reboot Raspberry Pi?"))
        return;

    fetch("/api/reboot", { method: "POST" })
        .then(response => response.json())
        .then(() => setStatus("Rebooting… the page will reconnect in about a minute", "#f39c12"))
        .catch(err => console.error(err));
}

// ------------------------------------------------------------
// Timer interval selection (0, 24, 48 or 72 h)
// ------------------------------------------------------------

function timerChanged()
{
    const timerSelect = document.getElementById("timerHours");
    const hours = parseInt(timerSelect.value, 10);

    fetch("/api/timer", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ timerInterval: hours })
    })
        .then(response =>
        {
            if (!response.ok)
                setStatus("Failed to update timer", "#e74c3c");
            timerSelect.blur();
            timerSelectBusy = false;
            updateTelemetry();
        })
        .catch(error => console.error(error));
}
