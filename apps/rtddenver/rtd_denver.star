"""
Applet: RTD Denver
Summary: Live RTD transit times
Description: Shows real-time bus and train arrival times for Denver RTD stops. Displays upcoming departures with color-coded urgency based on your walk time.
Author: wfmer
"""

load("encoding/json.star", "json")
load("http.star", "http")
load("render.star", "render")
load("schema.star", "schema")

# RTD GTFS-RT feeds are protobuf-only; this proxy converts them to JSON.
# Source: https://github.com/wfmer/rtd-proxy (Cloud Run, always-on)
PROXY_URL = "https://rtd-proxy-194821693431.us-central1.run.app"

RTD_BLUE = "#003DA5"
RTD_LIGHT_BLUE = "#0099CC"

DEFAULT_STOP_ID = "11981"
DEFAULT_WALK_TIME = "5"

# Fixed urgency windows relative to walk time
LEAVE_NOW_WINDOW = 3
COMFORTABLE_WINDOW = 8

def main(config):
    stop_id = config.get("stop_id", DEFAULT_STOP_ID)
    walk_time = int(config.get("walk_time", DEFAULT_WALK_TIME))

    rep = http.get("%s/predictions/%s" % (PROXY_URL, stop_id), ttl_seconds = 30)
    if rep.status_code != 200:
        return error_screen("RTD unavailable")

    data = json.decode(rep.body())
    stop_name = data.get("stop_name", "") or ("Stop %s" % stop_id)
    predictions = data.get("predictions", [])

    if len(predictions) == 0:
        return no_service_screen(stop_name)

    # One next arrival per route, up to 3 routes
    route_order = []
    routes = {}
    for pred in predictions:
        route = pred.get("route", "?")
        if route not in routes:
            route_order.append(route)
            routes[route] = {
                "headsign": pred.get("headsign", ""),
                "minutes": pred.get("minutes", 0),
                # Per-route brand color from static GTFS (fall back to RTD blue)
                "color": pred.get("color") or RTD_LIGHT_BLUE,
                "text_color": pred.get("text_color") or "#ffffff",
            }

    rows = []
    for i in range(min(3, len(route_order))):
        route = route_order[i]
        info = routes[route]
        minutes = info["minutes"]
        time_str = "Now" if minutes == 0 else "%dm" % minutes
        rows.append(make_route_row(route, info["headsign"], time_str, urgency_color(minutes, walk_time), info["color"], info["text_color"]))

    return render.Root(
        delay = 100,
        show_full_animation = True,
        child = render.Column(
            main_align = "start",
            cross_align = "start",
            children = [make_header(stop_name)] + rows,
        ),
    )

def make_header(stop_name):
    return render.Box(
        width = 64,
        height = 9,
        color = RTD_BLUE,
        child = render.Padding(
            pad = (2, 0, 0, 0),
            child = render.Marquee(
                width = 60,
                child = render.Text(content = stop_name, color = "#ffffff", font = "tom-thumb"),
                offset_start = 0,
                offset_end = 32,
            ),
        ),
    )

def make_route_row(route, headsign, time_str, color, badge_color, badge_text_color):
    # Layout (64px total): 1px pad + 16px badge + 2px gap + 28px dest + 1px gap + 16px time = 64px
    badge = render.Box(
        width = 16,
        height = 7,
        color = badge_color,
        child = render.Text(content = route[:4], color = badge_text_color, font = "tom-thumb"),
    )

    # Fixed 16px box prevents overflow; "Now"/"99m" are both 14px at tom-thumb
    time_widget = render.Box(
        width = 16,
        height = 7,
        child = render.Text(content = time_str, color = color, font = "tom-thumb"),
    )

    dest_widget = render.Marquee(
        width = 28,
        child = render.Text(content = headsign, color = "#cccccc", font = "tom-thumb"),
        offset_start = 0,
        offset_end = 5,
    )

    return render.Box(
        width = 64,
        height = 7,
        child = render.Padding(
            pad = (1, 1, 0, 0),
            child = render.Row(
                main_align = "start",
                cross_align = "center",
                expanded = True,
                children = [
                    badge,
                    render.Box(width = 2, height = 7),
                    dest_widget,
                    render.Box(width = 1, height = 7),
                    time_widget,
                ],
            ),
        ),
    )

def urgency_color(minutes, walk_time):
    if minutes < walk_time:
        return "#ff3333"
    elif minutes < walk_time + LEAVE_NOW_WINDOW:
        return "#ff9900"
    elif minutes < walk_time + COMFORTABLE_WINDOW:
        return "#ffdd00"
    else:
        return "#33cc33"

def no_service_screen(stop_name):
    return render.Root(
        child = render.Column(
            main_align = "start",
            cross_align = "start",
            children = [
                make_header(stop_name),
                render.Box(
                    width = 64,
                    height = 23,
                    child = render.Column(
                        main_align = "center",
                        cross_align = "center",
                        children = [
                            render.Text("No service", color = "#aaaaaa", font = "tom-thumb"),
                            render.Box(height = 2),
                            render.Text("Check schedule", color = "#666666", font = "tom-thumb"),
                        ],
                    ),
                ),
            ],
        ),
    )

def error_screen(msg):
    return render.Root(
        child = render.Box(
            child = render.Column(
                main_align = "center",
                cross_align = "center",
                children = [
                    render.Text("RTD", color = RTD_LIGHT_BLUE, font = "6x13"),
                    render.Text(msg, color = "#ff3333", font = "tom-thumb"),
                ],
            ),
        ),
    )

def get_schema():
    return schema.Schema(
        version = "1",
        fields = [
            schema.Text(
                id = "stop_id",
                name = "RTD Stop ID",
                desc = "Your RTD stop ID. Find it at rtd-denver.com or on the stop sign post.",
                icon = "bus",
                default = DEFAULT_STOP_ID,
            ),
            schema.Dropdown(
                id = "walk_time",
                name = "Walk time (minutes)",
                desc = "Minutes to walk to the stop. Arrivals sooner than this show red.",
                icon = "personWalking",
                default = DEFAULT_WALK_TIME,
                options = [
                    schema.Option(display = "2 min", value = "2"),
                    schema.Option(display = "5 min", value = "5"),
                    schema.Option(display = "8 min", value = "8"),
                    schema.Option(display = "10 min", value = "10"),
                    schema.Option(display = "12 min", value = "12"),
                    schema.Option(display = "15 min", value = "15"),
                    schema.Option(display = "20 min", value = "20"),
                ],
            ),
        ],
    )
