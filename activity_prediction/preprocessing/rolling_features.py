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
    "--also_save_non_overlapping/--dont_save_non_overlapping",
    help="Flag for whether or not to also save the non-overlapping version of the rolling window features.",
)
@click.option(
    "--save_dir",
    help="Path to the directory for saving the steps and heart rate rolling features (as two separate pickle files).",
)
def main(
    cleaned_steps_path,
    cleaned_hr_path,
    window_size,
    also_save_non_overlapping,
    save_dir,
):
    """Create and save rolling window features using the cleaned HR
    (seconds) and steps (minutes) data.

    For a single observation/row, rolling window functions calculate a
    summary metric (e.g. mean) using that observation and X preceding
    observations, where the X preceding observations are within
    ``window_size`` (e.g. 10min) of the current observation. This is
    implemented using ``pandas.DataFrame.rolling``.

    About --also_save_non_overlapping: By default, (pandas) rolling
    windows are calculated on every single observation such that,
    depending on the window size, consecutive windows can contain many
    overlapping/common observations. However, by choosing only one
    window per ``window_size`` amount of time, we can save the
    non-overlapping version of these rolling features.

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

    if also_save_non_overlapping:
        # steps
        no_overlap_steps_df = (
            df_dict["Steps_features"]
            .groupby(["Id", pd.Grouper(level="ActivityMinute", freq=window_size)])
            .first()
        )
        no_overlap_steps_save_path = os.path.join(
            save_dir,
            f"steps_rolling_features_df_window={window_size}_no-overlap.pickle",
        )
        with open(no_overlap_steps_save_path, "wb") as f:
            pickle.dump(no_overlap_steps_df, f)
        print(
            f"Saved non-overlapping steps rolling features to {no_overlap_steps_save_path}."
        )

        # HR
        no_overlap_hr_df = (
            df_dict["HR_features"]
            .groupby(["Id", pd.Grouper(level="Time", freq=window_size)])
            .first()
        )
        no_overlap_hr_save_path = os.path.join(
            save_dir, f"hr_rolling_features_df_window={window_size}_no-overlap.pickle",
        )
        with open(no_overlap_hr_save_path, "wb") as f:
            pickle.dump(no_overlap_hr_df, f)
        print(
            f"Saved non-overlapping HR rolling features to {no_overlap_hr_save_path}."
        )

if __name__ == "__main__":
    main()