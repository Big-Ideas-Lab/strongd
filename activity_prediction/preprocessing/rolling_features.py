import pandas as pd
import numpy as np
from tqdm import tqdm
import pickle
import click
import os

import helperfuns


@click.command()
@click.option(
    "--cleaned_steps_path",
    help="Path to the pickle file containing the cleaned Fitabase/Fitbit steps data. These data are a pandas dataframe with 'Id' as the first index, 'ActivityMinute' as the second (datetime) index, and 'Steps' as the only column.",
)
@click.option(
    "--cleaned_hr_path",
    help="Path to the pickle file containing the cleaned Fitabase/Fitbit heart rate data. These data are a pandas dataframe with 'Id' as the first index, 'Time' as the second (datetime) index, and 'Value' as the only column.",
)
@click.option(
    "--window_size",
    help="Window size used for pandas rolling window functions. This must use pandas's 'offset alias' syntax (see https://pandas.pydata.org/pandas-docs/stable/user_guide/timeseries.html#offset-aliases), e.g. '10min'.",
)
@click.option(
    "--save_dir",
    help="Path to the directory for saving the steps and heart rate rolling features (as two separate pickle files).",
)

def main(cleaned_steps_path, cleaned_hr_path, window_size, save_dir):
    """Create and save rolling window features using the cleaned HR
    (seconds) and steps (minutes) data.

    For a single observation/row, rolling window functions calculate a
    summary metric (e.g. mean) using that observation and X preceding
    observations, where the X preceding observations are within
    ``window_size`` (e.g. 10min) of the current observation. This is
    implemented using ``pandas.DataFrame.rolling``.

    The rolling window functions used for both steps and HR data are:
    mean, standard deviation, minimum, maximum, median, 25th quantile,
    and 75th quantile.
    """
    steps_df, hr_df = helperfuns.load_data(
        steps_path=cleaned_steps_path,
        hr_path=cleaned_hr_path,
        validate_ids=True,
        sort=True,
        sample_num=None,
    )

    # Remove all step data on a day if the total number of steps is zero
    # on that day
    steps_df = helperfuns.remove_zero_daily_steps(steps_df)

    df_dict = {"Steps": steps_df, "HR": hr_df}
    measurements = list(df_dict.keys())
    print("Creating steps and HR rolling features.")
    pbar = tqdm(total=14)  # open custom progress bar
    for measurement in measurements:
        df = df_dict[measurement].copy()

        # use only the second datetime index for time-based rolling
        # functions
        group = df.reset_index(0).groupby("Id")

        # rolling functions
        df[f"{measurement}_mean"] = group.rolling(window=window_size).mean().values
        df[f"{measurement}_std"] = group.rolling(window=window_size).std().values
        pbar.update(2)
        df[f"{measurement}_min"] = group.rolling(window=window_size).min().values
        df[f"{measurement}_max"] = group.rolling(window=window_size).max().values
        pbar.update(2)
        df[f"{measurement}_median"] = group.rolling(window=window_size).median().values
        df[f"{measurement}_quant25"] = (
            group.rolling(window=window_size).quantile(0.25).values
        )
        df[f"{measurement}_quant75"] = (
            group.rolling(window=window_size).quantile(0.75).values
        )
        pbar.update(3)

        df_dict[f"{measurement}_features"] = df

    pbar.close()  # close custom progress bar

    steps_save_path = os.path.join(
        save_dir, f"steps_rolling_features_df_window={window_size}.pickle"
    )
    with open(steps_save_path, "wb") as f:
        pickle.dump(df_dict["Steps_features"], f)
    print(f"Saved steps rolling features to {steps_save_path}.")

    hr_save_path = os.path.join(
        save_dir, f"hr_rolling_features_df_window={window_size}.pickle"
    )
    with open(hr_save_path, "wb") as f:
        pickle.dump(df_dict["HR_features"], f)
    print(f"Saved HR rolling features to {hr_save_path}.")

    return (df_dict["Steps_features"], df_dict["HR_features"])

