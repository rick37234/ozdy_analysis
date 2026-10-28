import os
from getpass import getpass

import pandas as pd
from sqlalchemy import create_engine
from sqlalchemy.engine import URL

url = URL.create(
    "postgresql+psycopg2",
    username="postgres",
    password=getpass("Postgres Password: "),
    host="localhost",
    port=5432,
    database="soccer"
)

engine = create_engine(url)

matches = pd.read_csv("data/matches.csv")
matches.to_sql("matches", engine, if_exists="replace", index=False)
print("matches: ", len(matches))

events = pd.concat([pd.read_pickle(f"data/events/{f}") for f in os.listdir("data/events")],
                   ignore_index=True)

for col in ["location", "pass_end_location", "shot_end_location", "carry_end_location",
            "goalkeeper_end_location"]:
    if col in events.columns:
        events[f"{col}_x"] = events[col].str[0]
        events[f"{col}_y"] = events[col].str[1]
events["shot_end_location_z"] = events["shot_end_location"].str[2]

nested = [c for c in events.columns
          if events[c].map(lambda v: isinstance(v, (list, dict))).any()]
# drops nested columns
print("nested - ", nested)
events = events.drop(columns=nested)

events.to_sql("events", engine, if_exists="replace", index=False, chunksize=10000)
print("events: ", len(events))

def to_minutes(clock):
    if not isinstance(clock, str):
        return None
    mins,secs = clock.split(":")
    return int(mins) + int(secs) / 60

players, stints = [],[]
for f in os.listdir("data/lineups"):
    match_id = int(f.replace(".pkl", ""))
    for team, table in pd.read_pickle(f"data/lineups/{f}").items():
        for _, p in table.iterrows():
            players.append({"match_id": match_id, "team": team, "player_id": p["player_id"],
                            "player_name": p["player_name"], "jersey_number": p["jersey_number"]})
            for s in p["positions"]:
                stints.append({"match_id": match_id, "team": team, "player_id": p["player_id"],
                               "position": s["position"],
                               "start_minute": to_minutes(s["from"]),
                               "end_minute": to_minutes(s["to"]),
                               "start_reason": s["start_reason"],
                               "end_reason": s["end_reason"]})

pd.DataFrame(players).to_sql("lineups", engine, if_exists="replace", index=False)
pd.DataFrame(stints).to_sql("player_positions", engine, if_exists="replace", index=False)

print("lineups: ", len(players), ", player_positions: ", len(stints))
