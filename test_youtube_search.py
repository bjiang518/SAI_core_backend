"""
Quick test script for YouTube Data API v3 educational video search.
Tests search quality across our whitelisted edu channels.

Usage:
    python test_youtube_search.py
    python test_youtube_search.py "mitosis cell division"
"""

import sys
import json
import urllib.request
import urllib.parse

API_KEY = "AIzaSyDsjeczjcgKtUD1zjX_owoR33TqwdsDnJM"
MAX_RESULTS = 5

EDU_CHANNELS = {
    "UC4a-Gbdw7vOaccHmFo40b9g": "Khan Academy",
    "UCX6b17PVsYBQ0ip5gyeme-Q": "CrashCourse",
    "UCYO_jab_esuFRV4b17AJtAg": "3Blue1Brown",
    "UCEBb1b_L6zDS3xTUrIALZOw": "MIT OpenCourseWare",
    "UCsooa4yRKGN_zEE8iknghZA": "TED-Ed",
    "UCEWpbFLzoYGPfuWUMFPSaoA": "Organic Chemistry Tutor",
    "UCoHhuummRZaIVX7bD4t2czg": "Professor Leonard",
}

TEST_QUERIES = [
    "mitosis cell division",
    "quadratic formula explained",
    "photosynthesis process",
    "Newton's laws of motion",
    "French Revolution causes",
    "integration by parts calculus",
    "supply and demand economics",
]


def search_videos(query: str, max_results: int = MAX_RESULTS) -> list:
    """Search YouTube, return results filtered to edu channels."""
    params = urllib.parse.urlencode({
        "part": "snippet",
        "q": query,
        "type": "video",
        "videoDuration": "medium",       # 4–20 min — best for educational content
        "videoEmbeddable": "true",
        "relevanceLanguage": "en",
        "maxResults": max_results * 3,   # fetch more so filtering doesn't leave us empty
        "key": API_KEY,
    })
    url = f"https://www.googleapis.com/youtube/v3/search?{params}"

    req = urllib.request.Request(url, headers={"Accept": "application/json"})
    with urllib.request.urlopen(req, timeout=10) as resp:
        data = json.loads(resp.read())

    results = []
    for item in data.get("items", []):
        channel_id = item["snippet"]["channelId"]
        video_id = item["id"].get("videoId")
        if not video_id:
            continue

        is_edu = channel_id in EDU_CHANNELS
        results.append({
            "videoId": video_id,
            "title": item["snippet"]["title"],
            "channel": item["snippet"]["channelTitle"],
            "channelId": channel_id,
            "is_edu_channel": is_edu,
            "edu_channel_name": EDU_CHANNELS.get(channel_id, ""),
            "url": f"https://youtube.com/watch?v={video_id}",
        })

    # Sort: edu channel hits first, then the rest
    results.sort(key=lambda x: (0 if x["is_edu_channel"] else 1))
    return results[:max_results]


def print_results(query: str, results: list):
    print(f"\n{'='*60}")
    print(f"Query: \"{query}\"")
    print(f"{'='*60}")
    if not results:
        print("  No results returned.")
        return
    for i, r in enumerate(results, 1):
        edu_tag = f" ✅ [{r['edu_channel_name']}]" if r["is_edu_channel"] else " ○ [open web]"
        print(f"  {i}.{edu_tag}")
        print(f"     Title:   {r['title']}")
        print(f"     Channel: {r['channel']}")
        print(f"     URL:     {r['url']}")


def run_tests(queries: list):
    edu_hit_count = 0
    total = 0

    for query in queries:
        try:
            results = search_videos(query)
            print_results(query, results)
            top_is_edu = results[0]["is_edu_channel"] if results else False
            if top_is_edu:
                edu_hit_count += 1
            total += 1
        except Exception as e:
            print(f"\n[ERROR] Query \"{query}\": {e}")

    print(f"\n{'='*60}")
    print(f"Summary: top result was an edu channel in {edu_hit_count}/{total} queries")
    print(f"{'='*60}\n")


if __name__ == "__main__":
    if len(sys.argv) > 1:
        # Single custom query passed as argument
        query = " ".join(sys.argv[1:])
        try:
            results = search_videos(query)
            print_results(query, results)
        except Exception as e:
            print(f"[ERROR] {e}")
    else:
        # Run all test queries
        run_tests(TEST_QUERIES)
