import pandas as pd
import pickle


def main():
    labels = pd.read_csv(
        "labels/24HourFitnessUsage with Randomization Arms added.xlsx - STRONGD.csv"
    )

    # combine "Date" and "Time" columns and convert into one pandas datetime column called "Time"
    datetime = labels["Date"].str.cat(labels["Time"], sep=" ")
    labels.drop(["Date", "Time"], axis=1, inplace=True)
    labels["Time"] = pd.to_datetime(datetime, format="%m/%d/%Y %I:%M:%S%p")

    # rename columns and shorten arm descriptions
    labels.rename(
        columns={"Participant ID": "Id", "Randomization Arm": "Arm"}, inplace=True
    )
    labels["Arm"] = labels["Arm"].replace(
        [
            "Arm 1: Strength Training Only",
            "Arm 2: Aerobic Training Only",
            "Arm 3: Combination (Aerobic and Strength) Training",
        ],
        ["strength", "aerobic", "combined"],
    )

    # set Id, Time as indices
    labels.set_index(["Id", "Time"], inplace=True)

    # save
    with open("clean_data/labels_df.pickle", "wb") as f:
        pickle.dump(labels, f)


if __name__ == "__main__":
    main()
