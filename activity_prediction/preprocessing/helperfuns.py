import pandas as pd
import pickle
import random

def load_data(steps_path, hr_path, validate_ids=True, sort=True, sample_num=None):
    """Load steps and HR data from pickle files

    :param steps_path: path to the pickle file containing a pandas dataframe of steps data with "Id" as the first index and "ActivityMinute" as the second (datetime) index.
    :param hr_path: path to the pickle file containing a pandas dataframe of HR data with "Id" as the first index and "Time" as the second (datetime) index.
    :param validate_ids: boolean that indicates whether to check that the steps and HR dataframes have the same set of values in their "Id" index, defaults to True.
    :param sort: boolean that indicates whether to sort the steps and HR dataframes by their first and second indices (in this order), defaults to True.
    :param sample_num: number of participants to sample for returning a subset of the steps and HR dataframes. Set this to ``None`` to get the full steps and HR dataframes. Defaults to None.
    :return: a tuple of two pandas dataframes: (steps_df, hr_df).
    """

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

def remove_zero_daily_steps(steps_df):
    """Remove all step data on a day if the total number of steps is zero on that day

    Note that the input dataframe (``steps_df``) is changed inplace and will be changed in the caller function.

    :steps_df: pandas dataframe with participant ID on the first index and datetime on the second index. The first index must be named "Id" and the second index must be named "ActivityMinute".
    """
    print("Removing all step data on a day if the total number of steps is zero on that day.")

    # get date from the datetime index
    steps_df['date'] = steps_df.index.get_level_values(1).date

    # re-index on participant ID and date (not datetime)
    steps_df.reset_index(inplace=True)
    steps_df.set_index(['Id', 'date'], inplace=True)

    # create an indexing mask to retain only days when the daily total number of steps is above zero
    daily_steps = steps_df.groupby(['Id', 'date']).Steps.sum()
    mask = daily_steps[daily_steps > 0].index
    steps_df = steps_df.loc[mask]

    # re-index back to the original index (Id, ActivityMinute)
    steps_df.reset_index(inplace=True)
    steps_df.set_index(['Id', 'ActivityMinute'], inplace=True)

    # drop the date column
    steps_df.drop('date', axis=1, inplace=True)

    return steps_df
