import pandas as pd
import numpy as np
from scipy import signal
from tqdm import tqdm
import pickle
import click
import os
import matplotlib.pyplot as plt
import plotly.graph_objects as go


@click.command()
@click.option(
    "--cleaned_steps_path",
    help="Path to the pickle file containing the cleaned Fitabase/Fitbit steps data.",
)
@click.option(
    "--cleaned_hr_path",
    help="Path to the pickle file containing the cleaned Fitabase/Fitbit heart rate data.",
)
@click.option(
    "--window_size",
    help="Number of consecutive samples used to calculate each Fourier transform within the spectrogram. This corresponds to the ``nperseg`` parameter in scipy.signal.spectrogram.",
    type=int,
)
@click.option(
    "--save_dir",
    help="Path to the directory for saving the steps and heart rate spectrogram features (as two separate pickle files).",
)
def main(cleaned_steps_path, cleaned_hr_path, window_size, save_dir):
    """
    Create and save spectrogram features using the cleaned HR (seconds)
    and steps (minutes) data.
    """
    with open(cleaned_steps_path, "rb") as f:
        steps_df = pickle.load(f)

    with open(cleaned_hr_path, "rb") as f:
        hr_df = pickle.load(f)

    id_set = set(steps_df.index.get_level_values(0).unique())
    # check that the HR and steps data have the same set of participant IDs
    assert id_set == set(hr_df.index.get_level_values(0).unique())

    print("Sorting steps and HR data by participant ID and then timestamp.")
    steps_df.sort_index(level=["Id", "ActivityMinute"], inplace=True)
    hr_df.sort_index(level=["Id", "Time"], inplace=True)

    print("Creating steps and HR spectrogram features for each participant.")
    steps_features_dict = dict()
    hr_features_dict = dict()
    for participant_id in tqdm(id_set):
        steps_features_df, _ = get_participant_spectrogram_features(
            participant_df=steps_df.loc[participant_id],
            time_delta_threshold=pd.Timedelta("1hour"),
            spectrogram_col="Steps",
            spectrogram_samples_per_sec=1 / 60,
            spectrogram_window_size=window_size,
        )
        steps_features_dict[participant_id] = steps_features_df

        hr_features_df, _ = get_participant_spectrogram_features(
            participant_df=hr_df.loc[participant_id],
            time_delta_threshold=pd.Timedelta("1hour"),
            spectrogram_col="Value",
            spectrogram_samples_per_sec=1 / 5,
            spectrogram_window_size=window_size,
        )
        hr_features_dict[participant_id] = hr_features_df

    # concatenate all participants' features
    all_steps_features_df = pd.concat(steps_features_dict).rename_axis(["Id", "Time"])
    all_hr_features_df = pd.concat(hr_features_dict).rename_axis(["Id", "Time"])

    steps_save_path = os.path.join(
        save_dir, f"steps_spectrogram_features_df_window={window_size}.pickle"
    )
    with open(steps_save_path, "wb") as f:
        pickle.dump(all_steps_features_df, f)
    print("Saved steps spectrogram features.")

    hr_save_path = os.path.join(
        save_dir, f"hr_spectrogram_features_df_window={window_size}.pickle"
    )
    with open(hr_save_path, "wb") as f:
        pickle.dump(all_hr_features_df, f)
    print("Saved HR spectrogram features.")

    return (all_steps_features_df, all_hr_features_df)


def get_participant_spectrogram_features(
    participant_df,
    time_delta_threshold,
    spectrogram_col,
    spectrogram_samples_per_sec,
    spectrogram_window_size,
):
    """Get spectrogram features for a single participant.

    This function calculates spectrograms (using Windowed/Short-Time
    Fourier Transforms; see
    https://en.wikipedia.org/wiki/Short-time_Fourier_transform) on
    Fitbase/Fitbit steps or heart rate (HR) data for a single
    participant. 

    Usually, Fourier transforms and spectrograms assume a constant
    sampling rate in the data, but this is not the case in the Strong-D
    Fitbit data: most but not all steps data are sampled at 1
    observation per minute, and many but not all HR data are sampled at
    1 observation per 5 seconds. For large gaps in the sampling rate,
    e.g. 1 hour, this function calculates separate spectrograms for the
    data before versus after the large gap (see the
    ``time_delta_threshold`` parameter). For other smaller
    inconsistencies in the sampling rate, e.g. 1 second versus 5 second
    delta between consecutive observations, this function calculates one
    spectrogram that *assumes* a constant sampling rate. 

    For Strong-D steps data, the assumed constant sampling rate is 1
    sample per min (median time delta between consecutive steps
    observations); for Strong-D HR data, the assumed constant sampling
    rate is 1 sample per 5s (median time delta between consecutive HR
    observations).

    :param participant_df: pandas dataframe indexed on a datetime
        column. This contains data for a *single* participant and
        contains the column specified in the parameter
        ``spectrogram_col`` in addition to the datetime index. 
    :param time_delta_threshold: a pandas.Timedelta object. If two
        consecutive timestamps T1 and T2 in participant_df have ``(T2 -
        T1) > time_delta_threshold``, then separate spectrograms will be
        returned for observations preceding (and including) T1 versus
        observations following (and including) T2.
    :spectrogram_col: name of the non-datetime column that we are
        calculating the spectrogram (windowed Fourier transformations)
        on.
    :spectrogram_samples_per_sec: sample frequency (in number of samples
        per sec) used for calculating the spectrogram. This corresponds
        to the ``fs`` parameter in scipy.signal.spectrogram. Note that
        you might assume a constant sample frequency of 1/60 if the
        median time delta between consecutive samples/rows in your data
        is 1min.
    :spectrogram_window_size: number of consecutive samples used to
        calculate each windowed Fourier transform within the
        spectrogram. This corresponds to the ``nperseg`` parameter in
        scipy.signal.spectrogram. 
    :returns: a tuple ``(features_df, spectrograms)``. ``spectrograms`` 
        is a pandas series containing >=1 spectrograms (see the
        ``time_delta_threshold`` parameter to understand how there can
        be more than one spectrogram), where each spectrogram follows
        the format returned by scipy.signal.spectrogram. ``features_df``
        is a pandas dataframe that concatenates and transposes all
        spectrograms in ``spectrograms`` such that the index is the
        datetime and each column is a frequency band.
    """

    # assert that the dataframe is sorted on its index (time)
    assert all(participant_df.index == participant_df.index.sort_values())

    # find the time deltas between consecutive time stamps
    participant_df["time"] = participant_df.index
    delta = (participant_df["time"] - participant_df["time"].shift()).fillna(
        pd.Timedelta("0")
    )
    participant_df["delta"] = delta.values

    # if there exists time deltas greater than time_delta_threshold,
    # then assign different groups to each "chunk" of time ranges that
    # don't exceed time_delta_threshold
    indices = participant_df[participant_df.delta > time_delta_threshold].index
    participant_df["group"] = 0
    for i in range(len(indices)):
        if i == len(indices) - 1:
            participant_df.loc[indices[i] :, "group"] = i + 1
            continue

        participant_df.loc[indices[i] : indices[i + 1], "group"].iloc[:-1] = (
            i + 1
        )  # iloc[:-1] makes the endpoint noninclusive

    participant_df["group"] = participant_df["group"].astype("category")

    # one-sided spectrogram
    get_spectrogram = lambda x: signal.spectrogram(
        x,
        fs=spectrogram_samples_per_sec,
        nperseg=spectrogram_window_size,
        noverlap=None,
        mode="magnitude",
    )
    # num freq bands = nperseg/2 + 1

    # create a spectrogram for each group, where the time delta is under
    # time_delta_threshold within each group
    spectrograms = participant_df.groupby("group")[spectrogram_col].apply(
        get_spectrogram
    )

    # reshape the spectrograms into dataframes (indexed by time), where
    # each frequency band is its own field/column
    features_list = []
    for i in range(len(spectrograms)):
        # extract the frequency, time and spectrogram values
        (f, t, Sxx) = spectrograms.loc[i]

        # retrieve the original timestamps
        time = participant_df.groupby("group").get_group(i).index[0] + pd.to_timedelta(
            t, unit="s"
        )

        # reshape the spectrogram into a dataframe, where time becomes
        # the index and each frequency band becomes a column
        features_list.append(
            pd.DataFrame(
                data=Sxx.T,
                index=time,
                columns=[
                    "spectrogram_" + str(np.round(f[i], 5)) + "Hz"
                    for i in range(len(f))
                ],
            )
        )

    features_df = pd.concat(features_list)

    return (features_df, spectrograms)


def plot_spectrogram(spectrogram, interactive=True):
    (f, t, Sxx) = spectrogram

    x_label = "Time (seconds elapsed)"
    y_label = "Frequency Bands (Hz)"
    if interactive:
        fig = go.Figure(
            data=go.Heatmap(z=Sxx, x=t, y=f),
            layout=go.Layout(xaxis=dict(title=x_label), yaxis=dict(title=y_label)),
        )
        fig.show()
    else:
        plt.pcolormesh(t, f, Sxx)
        plt.ylabel(y_label)
        plt.xlabel(x_label)
        plt.show()


if __name__ == "__main__":
    main()
