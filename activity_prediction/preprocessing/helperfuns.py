import pandas as pd
import pickle
import random

# TODO: docs
def load_data(steps_path, hr_path, validate_ids=True, sort=True, sample_num=None):
    with open(steps_path, "rb") as f:
        steps_df = pickle.load(f)

    with open(hr_path, "rb") as f:
        hr_df = pickle.load(f)

    id_set = set(steps_df.index.get_level_values(0).unique())
    if validate_ids:
        print(
            "Validating that the steps and HR data have the same set of participant IDs."
        )
        # check that the HR and steps data have the same set of participant IDs
        assert id_set == set(hr_df.index.get_level_values(0).unique())

    if sample_num:
        print(f"Subsetting the steps and HR data to {sample_num} sample participants.")
        sample_ids = random.sample(id_set, sample_num)
        steps_df = steps_df.loc[sample_ids]
        hr_df = hr_df.loc[sample_ids]

    if sort:
        print("Sorting steps and HR data by participant ID and then timestamp.")
        steps_df.sort_index(level=["Id", "ActivityMinute"], inplace=True)
        hr_df.sort_index(level=["Id", "Time"], inplace=True)

    return (steps_df, hr_df)

