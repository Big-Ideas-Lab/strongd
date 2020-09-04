import pandas as pd
import numpy as np
import pickle
import click


@click.command()
@click.option(
    "--window_size",
    help="Window size used for generating the features to be merged. This must use pandas's 'offset alias' syntax (see https://pandas.pydata.org/pandas-docs/stable/user_guide/timeseries.html#offset-aliases), e.g. '10min'.",
)
@click.argument(
    "feature_paths", nargs=-1,
)
@click.argument("save_path", nargs=1)
def main(window_size, feature_paths, save_path):
    """Merge features and labels onto the same timeline

    Uses pandas.merge_asof, which is a left join that matches on the
    closest observation in time.

    FEATURE_PATHS: Space-separated paths to the pickle files containing
    the features (pandas dataframes) to merge. The merging will perform
    time-based left joins in the same order as the paths listed here.
    Note that each of these feature files should have been generated
    using the same window size specified in the --window_size option.
    
    SAVE_PATH: Path for saving the merged features as a pickle file.
    """

    merged = None
    # merge all features
    for path in feature_paths:
        to_merge = pickle.load(open(path, "rb"))
        to_merge.index.rename(["Id", "Time"], inplace=True)

        # check if dataframe contains spectrogram features
        if any(["spectrogram" in x for x in to_merge.columns]):
            # keep only the frequency bands/columns with the most
            # contribution to the signal
            to_merge = get_top_frequency_bands(to_merge, n=5)

        if merged is None:  # first dataframe
            merged = to_merge
            start_nrows = merged.shape[0]
            print(f"The first feature file contains {start_nrows} rows.")

            # merge labels
            merged = merge_labels(
                merged, duration=pd.Timedelta("1H"), offset=pd.Timedelta("10min")
            )
            end_nrows = merged.shape[0]
            print(
                f"After merging (time-based left joins) with labels, the resulting dataframe contains {end_nrows} ({np.round(end_nrows/start_nrows*100, 2)}% of the starting number of rows)."
            )
            continue

        merged = merge_features(merged, to_merge, tolerance=window_size)
        merged.set_index(["Id", "Time"], inplace=True)

    end_nrows = merged.shape[0]
    print(
        f"After merging (time-based left joins) the features, the resulting dataframe contains {end_nrows} ({np.round(end_nrows/start_nrows*100, 2)}% of the starting number of rows)."
    )

    with open(save_path, "wb") as f:
        pickle.dump(merged, f)
    print(f"Saved the merged features and labels to {save_path}.")


# TODO: docs
def merge_features(df1, df2, tolerance, datetime_index="Time", id_index="Id"):
    """Merge timeseries features by finding the nearest match in time using pandas.merge_asof.

    :param df1: [description]
    :param df2: [description]
    :param tolerance: [description]
    :param datetime_index: [description], defaults to "Time"
    :param id_index: [description], defaults to "Id"
    :returns: [description]
    """
    merged = pd.merge_asof(
        df1.sort_index(level=datetime_index),
        df2.sort_index(level=datetime_index),
        on=datetime_index,
        by=id_index,
        tolerance=pd.Timedelta(tolerance),
        direction="nearest",
    )

    # drop records that don't have any matches from df2
    merged.dropna(inplace=True)

    return merged


def merge_labels(
    df,
    duration=pd.Timedelta("1H"),
    offset=pd.Timedelta("10min"),
    datetime_index="Time",
    id_index="Id",
    labels_path="clean_data/labels_df.pickle",
):
    """Merge the input dataframe with labels (Strong-D study arms)

    :param df: [description]
    :param offset: [description], defaults to pd.Timedelta("10min")
    :param duration: [description], defaults to pd.Timedelta("1H")
    :param labels_path: [description], defaults to "clean_data/labels_df.pickle"
    :returns: [description]
    """

    with open(labels_path, "rb") as f:
        labels_df = pickle.load(f)

    # drop any existing "Arm" label column
    df.drop("Arm", axis=1, inplace=True, errors="ignore")

    time = labels_df.index.get_level_values(1)

    # create new labels where the datetime index is shifted by the offset
    offset_df = labels_df.reset_index().drop(datetime_index, axis=1)
    offset_df[datetime_index] = time.shift(freq=offset)
    offset_df.set_index([id_index, datetime_index], inplace=True)

    # create "other" (non- aerobic/strength/combined) labels
    other_df = labels_df.reset_index().drop(datetime_index, axis=1)
    other_df[datetime_index] = time.shift(freq=-duration)
    other_df.set_index([id_index, datetime_index], inplace=True)
    other_df["Arm"] = "other"

    # only match the nearest labels (Strong-D study arms) to df
    # records/measurements if the (shifted) labels occur BEFORE the
    # measurement
    merged = pd.merge_asof(
        df.sort_index(level=datetime_index),
        offset_df.sort_index(level=datetime_index),
        on=datetime_index,
        by=id_index,
        tolerance=duration,
        direction="backward",
    )
    merged.set_index([id_index, datetime_index], inplace=True)

    # only match the nearest "other" (not an aerobic/strength/combined
    # study arm) labels to df records/measurements if the labels occur
    # BEFORE the measurement
    merged = pd.merge_asof(
        merged.sort_index(level=datetime_index),
        other_df.sort_index(level=datetime_index),
        on=datetime_index,
        by=id_index,
        tolerance=duration,
        direction="backward",
    )
    merged.set_index([id_index, datetime_index], inplace=True)

    # combine the arm labels with the "other" labels
    merged["Arm"] = merged["Arm_x"]
    merged.loc[pd.notna(merged["Arm_y"]), "Arm"] = merged[pd.notna(merged["Arm_y"])][
        "Arm_y"
    ]
    merged.drop(["Arm_x", "Arm_y"], axis=1, inplace=True)

    # drop any rows without labels
    merged.dropna(subset=["Arm"], inplace=True)

    return merged


def get_top_frequency_bands(spectrogram_features, n=5):
    """Keep only the top n spectrogram frequency bands/columns 10 with the largest average magnitudes/contributions

    :param spectrogram_features: [description]
    :param n: [description], defaults to 5
    :returns: [description]
    """
    desc = spectrogram_features.describe()
    bands_keep = list(desc.loc["mean"].sort_values(ascending=False)[:n].index)
    return spectrogram_features[bands_keep]


if __name__ == "__main__":
    main()
