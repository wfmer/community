"""
Applet: RTD Denver
Summary: Live RTD transit times
Description: Shows real-time bus and train arrival times for Denver RTD stops. Configure your stop ID in the app settings.
Author: Andrew Sharp
"""

load("encoding/json.star", "json")
load("http.star", "http")
load("render.star", "render")
load("schema.star", "schema")

# Public proxy URL (deployed on Google Cloud Run)
PROXY_URL = "https://rtd-proxy-194821693431.us-central1.run.app"

# Default values
DEFAULT_STOP_ID = "11981"
DEFAULT_WALK_TIME = "10"

def main(config):
    """Main function to render RTD arrival times"""
    stop_id = config.get("stop_id", DEFAULT_STOP_ID)
    walk_time = int(config.get("walk_time", DEFAULT_WALK_TIME))

    # Fetch predictions from public proxy
    url = "%s/predictions/%s" % (PROXY_URL, stop_id)

    rep = http.get(url, ttl_seconds = 0)  # No caching - always fetch fresh data

    if rep.status_code != 200:
        return render.Root(
            child = render.Box(
                child = render.WrappedText(
                    content = "Error loading RTD data",
                    color = "#ff0000",
                ),
            ),
        )

    data = json.decode(rep.body())
    predictions = data.get("predictions", [])

    if len(predictions) == 0:
        return render.Root(
            child = render.Box(
                child = render.Column(
                    main_align = "center",
                    cross_align = "center",
                    children = [
                        render.Text("RTD Stop %s" % stop_id, color = "#ffaa00", font = "tom-thumb"),
                        render.Text("No arrivals", color = "#ffffff", font = "tom-thumb"),
                    ],
                ),
            ),
        )

    # Build display for up to 3 predictions
    rows = []
    rows.append(render.Text("RTD Stop %s" % stop_id, color = "#ffaa00", font = "tom-thumb"))

    for i in range(min(3, len(predictions))):
        pred = predictions[i]
        route = pred.get("route", "?")
        minutes = pred.get("minutes", 0)

        # Color code based on urgency and walk time
        if minutes < walk_time:
            color = "#ff0000"  # Red - too late to catch
        elif minutes < walk_time + 8:
            color = "#ffaa00"  # Yellow - need to leave soon
        else:
            color = "#00ff00"  # Green - plenty of time

        rows.append(
            render.Row(
                children = [
                    render.Text("Rte %s: " % route, color = "#ffffff", font = "tom-thumb"),
                    render.Text("%d min" % minutes, color = color, font = "tom-thumb"),
                ],
            ),
        )

    return render.Root(
        delay = 25000,  # Refresh every 25 seconds
        show_full_animation = True,  # Force continuous re-rendering
        child = render.Box(
            child = render.Column(
                main_align = "start",
                cross_align = "start",
                children = rows,
            ),
        ),
    )

def get_schema():
    """Configuration schema for the Tidbyt mobile app"""
    return schema.Schema(
        version = "1",
        fields = [
            schema.Text(
                id = "stop_id",
                name = "RTD Stop ID",
                desc = "Enter your RTD stop ID (find at rtd-denver.com or on stop signs)",
                icon = "bus",
                default = DEFAULT_STOP_ID,
            ),
            schema.Dropdown(
                id = "walk_time",
                name = "Walk Time",
                desc = "How long does it take you to walk to the stop?",
                icon = "personWalking",
                default = DEFAULT_WALK_TIME,
                options = [
                    schema.Option(
                        display = "5 minutes",
                        value = "5",
                    ),
                    schema.Option(
                        display = "10 minutes",
                        value = "10",
                    ),
                    schema.Option(
                        display = "15 minutes",
                        value = "15",
                    ),
                    schema.Option(
                        display = "20 minutes",
                        value = "20",
                    ),
                ],
            ),
        ],
    )
