import pandas as pd
import pickle
import random
import json

random.seed(0)

from preprocessing import helperfuns
from preprocessing import merging

CLEANED_STEPS_PATH = "preprocessing/clean_data/steps_minutes_df.pickle"
CLEANED_HR_PATH = "preprocessing/clean_data/hr_seconds_df.pickle"
TEST_PARTICIPANT_RATIO = 0.2
SAVE_FILE = "train_test_participants.json"


def main():
    """Perform participant-conscious train-test split
    
    1. Remove participants whose step data doesn't merge with any labels
       (aerobic, strength, or combined)
    2. Remove participants in the "combined" arm
    3. Split the participants into training (80%) and testing (20%)
       groups
    4. Save as a json file specified by ``SAVE_FILE``
    
    """

    steps_df, hr_df = helperfuns.load_data(
        steps_path=CLEANED_STEPS_PATH,
        hr_path=CLEANED_HR_PATH,
        validate_ids=True,
        sample_num=None,
        subset_ids=None,
        sort=False,
    )

    steps_df.index.rename(["Id", "Time"], inplace=True)

    # for each row in steps_df, match labels that occur within 1hr
    # before the row's timestamp
    merged = merging.merge_labels(
        steps_df, labels_path="preprocessing/clean_data/labels_df.pickle",
    )

    all_participants = set(merged.index.get_level_values(0).unique())

    # find participants without any arm (strength/aerobic/combined)
    # labels, i.e. they only have the "other" label
    unique_labels = merged.groupby(level="Id")["Arm"].apply(lambda x: set(x.unique()))
    no_arms_participants = set(unique_labels[unique_labels == {"other"}].index)

    # find participants in the "combined" arm
    combined_participants = set(
        merged[merged["Arm"] == "combined"].index.get_level_values(0).unique()
    )

    # only keep participants that have labels and that are *not* in the
    # "combined" arm
    keep_participants = list(
        all_participants - no_arms_participants - combined_participants
    )
    keep_participants.sort()  # so that the random seed will reproduce the same splits
    num_participants = len(keep_participants)

    # separate train vs test participants
    test_num = int(num_participants * TEST_PARTICIPANT_RATIO)
    split_dict = dict()
    split_dict["test"] = random.sample(keep_participants, test_num)
    split_dict["train"] = list(set(keep_participants) - set(split_dict["test"]))
    split_dict["test"].sort()
    split_dict["train"].sort()

    # save as json file
    with open(SAVE_FILE, "w") as f:
        json.dump(split_dict, f)
    print(f"Saved the participant train-test split to {SAVE_FILE}.")


if __name__ == "__main__":
    main()
