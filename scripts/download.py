import os
import warnings

import pandas as pd
from statsbombpy import sb

warnings.filterwarnings('ignore')
# avail_comps = sb.competitions()
# print(avail_comps.columns)
# print(avail_comps[['competition_id',"competition_name","season_id","season_name"]].to_string())
# Comp ID - 2(Prem), 12(Serie A)
# Season ID - 27(15-16)

pl = sb.matches(competition_id=2, season_id=27)
seriea = sb.matches(competition_id=12, season_id=27)


arsenal = pl[(pl['home_team'] == 'Arsenal') | (pl['away_team'] == 'Arsenal')]
juve = seriea[(seriea['home_team'] == 'Juventus') | (seriea['away_team'] == 'Juventus')]

# print("Arsenal matches - ", len(arsenal), "\nJuventus matches - ", len(juve))

matches = pd.concat([arsenal, juve], ignore_index=True)
os.makedirs("data/events", exist_ok=True)
os.makedirs("data/lineups", exist_ok=True)
matches.to_csv("data/matches.csv", index=False)

for i, match_id in enumerate(matches['match_id'], start=1):
    events_path = f"data/events/{match_id}.pkl"
    lineups_path = f"data/lineups/{match_id}.pkl"
    if os.path.exists(events_path) and os.path.exists(lineups_path):
        continute
    sb.events(match_id=match_id).to_pickle(events_path)
    pd.to_pickle(sb.lineups(match_id=match_id), lineups_path)
    print(f"{i}/{len(matches)} saved match {match_id}")

print("Done - ", len(os.listdir("data/events")), "event files " , len(os.listdir("data/lineups")), "lineup files")