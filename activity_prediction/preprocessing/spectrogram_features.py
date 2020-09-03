import pandas as pd
import numpy as np
from scipy import signal
from tqdm import tqdm
import pickle
import click
import os
from pathlib import Path

import helperfuns

# majority (99.9996%) sampling rate in Strong-D step data
STEPS_SAMPLES_PER_SEC = 1 / 60
# mean sampling rate in Strong-D HR data
HR_SAMPLES_PER_SEC = 1 / 9
ID_LIST = [
    "32113-0004",
    "32113-0005",
    "32113-0007",
    "32113-0009",
    "32113-0011",
    "32113-0013",
    "32113-0014",
    "32113-0016",
    "32113-0017",
    "32113-0018",
    "32113-0020",
    "32113-0022",
    "32113-0025",
    "32113-0026",
    "32113-0028",
    "32113-0030",
    "32113-0031",
    "32113-0032",
    "32113-0033",
    "32113-0034",
    "32113-0036",
    "32113-0038",
    "32113-0040",
    "32113-0041",
    "32113-0042",
    "32113-0044",
    "32113-0045",
    "32113-0046",
    "32113-0047",
    "32113-0048",
    "32113-0051",
    "32113-0059",
    "32113-0060",
    "32113-0061",
    "32113-0063",
    "32113-0064",
    "32113-0065",
    "32113-0066",
    "32113-0067",
    "32113-0068",
    "32113-0070",
    "32113-0072",
    "32113-0073",
    "32113-0076",
    "32113-0078",
    "32113-0079",
    "32113-0080",
    "32113-0081",
    "32113-0082",
    "32113-0083",
    "32113-0085",
    "32113-0086",
    "32113-0089",
    "32113-0090",
    "32113-0093",
    "32113-0095",
    "32113-0097",
    "32113-0098",
    "32113-0099",
    "32113-0100",
    "32113-0106",
    "32113-0107",
    "32113-0108",
    "32113-0111",
    "32113-0112",
    "32113-0113",
    "32113-0114",
    "32113-0116",
    "32113-0118",
    "32113-0119",
    "32113-0120",
    "32113-0121",
    "32113-0123",
    "32113-0124",
    "32113-0135",
    "32113-0139",
    "32113-0142",
    "32113-0145",
]  # used for running slurm job arrays


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
    "--window_size_in_minutes",
    help="This determines the number of consecutive samples used to calculate each windowed/short-time Fourier transform within the spectrogram. Specifically, a single windowed Fourier transformation will use ``window_size_in_minutes * samples_per_minute`` samples/rows (e.g. 10min) from the input dataframe.",
    type=int,
)
@click.option(
    "--overlap/--no-overlap",
    help="Flag for whether or not to overlap the observations in the windows used to calculate the spectrogram. This flag and --window_size_in_minutes are used to derive the ``noverlap`` parameter in scipy.signal.spectrogram.",
)
@click.option(
    "--save_dir",
    help="Path to the directory for saving the steps and heart rate spectrogram features (as two separate pickle files).",
)
@click.option(
    "--concurrent/--not-concurrent",
    default=False,
    help="This is specific to Slurm job arrays: By turning on --concurrent and including ``#SBATCH --array=0_{num_participant_ids}`` in your job script, you will be able to run this python script as separate, concurrent jobs for each participant (instead of one large job for all participants). This is especially useful when you use --overlap and need to limit the amount of RAM used for each individual job.",
)
def main(
    cleaned_steps_path,
    cleaned_hr_path,
    window_size_in_minutes,
    overlap,
    save_dir,
    concurrent,
):
    """
    Create and save spectrogram features using the cleaned HR (seconds)
    and steps (minutes) data.

    The number of observations/samples to use for calculating the
    spectrogram is derived as: ``window_rows = (window_size_in_minutes *
    60) * SAMPLES_PER_SEC``, where the sampling rate is different for
    steps vs HR. This corresponds to the `nperseg`` parameter in
    scipy.signal.spectrogram.

    If the --overlap option is used, this function will use the maximum
    overlap between each windowed/short-time Fourier transform within
    the spectrogram: ``overlapping_rows = window_rows - 1`` (see
    paragraph above for ``window_rows``). Otherwise, for --no-overlap,
    ``overlapping_rows = 0``. This corresponds to the ``noverlap``
    parameter in scipy.signal.spectrogram.
    """

    subset_ids = None
    if concurrent:
        # choose one participant using the slurm array ID
        task_id = int(os.environ["SLURM_ARRAY_TASK_ID"])
        subset_ids = ID_LIST[task_id : task_id + 1]  # list of one element

        # make subdirectory under save_dir if it doesn't exist
        concurrent_save_dir = os.path.join(save_dir, "participant_spectrograms")
        Path(concurrent_save_dir).mkdir(exist_ok=True)

    steps_df, hr_df = helperfuns.load_data(
        steps_path=cleaned_steps_path,
        hr_path=cleaned_hr_path,
        validate_ids=True,
        sample_num=None,
        subset_ids=subset_ids,
        sort=True,
    )

    id_list = list(steps_df.index.get_level_values(0).unique())

    # Remove all step data on a day if the total number of steps is zero
    # on that day
    steps_df = helperfuns.remove_zero_daily_steps(steps_df)

    # derive the number of observations in the window
    steps_window_rows = int(window_size_in_minutes * 60 * STEPS_SAMPLES_PER_SEC)
    hr_window_rows = int(window_size_in_minutes * 60 * HR_SAMPLES_PER_SEC)

    # derive the number of observations to overlap
    steps_overlap = 0
    hr_overlap = 0
    if overlap:
        # maximum overlap between consecutive windows:
        steps_overlap = steps_window_rows - 1
        hr_overlap = hr_window_rows - 1

    print("Creating steps and HR spectrogram features for each participant.")
    steps_features_dict = dict()
    hr_features_dict = dict()
    for participant_id in tqdm(id_list):
        steps_features_df, _ = get_participant_spectrogram_features(
            participant_df=steps_df.loc[participant_id],
            time_delta_threshold=pd.Timedelta("1D"),
            spectrogram_col="Steps",
            spectrogram_samples_per_sec=STEPS_SAMPLES_PER_SEC,
            spectrogram_window_size=steps_window_rows,
            spectrogram_overlap_size=steps_overlap,
        )
        steps_features_dict[participant_id] = steps_features_df

        hr_features_df, _ = get_participant_spectrogram_features(
            participant_df=hr_df.loc[participant_id],
            time_delta_threshold=pd.Timedelta("1D"),
            spectrogram_col="Value",
            spectrogram_samples_per_sec=HR_SAMPLES_PER_SEC,
            spectrogram_window_size=hr_window_rows,
            spectrogram_overlap_size=hr_overlap,
        )
        hr_features_dict[participant_id] = hr_features_df

    # concatenate all participants' features
    all_steps_features_df = pd.concat(steps_features_dict).rename_axis(["Id", "Time"])
    all_hr_features_df = pd.concat(hr_features_dict).rename_axis(["Id", "Time"])

    steps_save_path = os.path.join(
        save_dir,
        f"steps_spectrogram_features_df_window={window_size_in_minutes}min_overlap={overlap}.pickle",
    )
    if concurrent:
        steps_save_path = os.path.join(
            concurrent_save_dir,
            f"steps_spectrogram_features_df_window={window_size_in_minutes}min_overlap={overlap}_participant={subset_ids[0]}.pickle",
        )
    with open(steps_save_path, "wb") as f:
        pickle.dump(all_steps_features_df, f)
    print(f"Saved steps spectrogram features to {steps_save_path}.")

    hr_save_path = os.path.join(
        save_dir,
        f"hr_spectrogram_features_df_window={window_size_in_minutes}min_overlap={overlap}.pickle",
    )
    if concurrent:
        hr_save_path = os.path.join(
            concurrent_save_dir,
            f"hr_spectrogram_features_df_window={window_size_in_minutes}min_overlap={overlap}_participant={subset_ids[0]}.pickle",
        )
    with open(hr_save_path, "wb") as f:
        pickle.dump(all_hr_features_df, f)
    print(f"Saved HR spectrogram features to {hr_save_path}.")

    return (all_steps_features_df, all_hr_features_df)


def get_participant_spectrogram_features(
    participant_df,
    time_delta_threshold,
    spectrogram_col,
    spectrogram_samples_per_sec,
    spectrogram_window_size,
    spectrogram_overlap_size,
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
    observation per minute, and most but not all HR data are sampled at
    1 observation per 3 seconds. 
    
    For large gaps in the sampling rate, e.g. 1 day, this function
    splits the input dataframe (``participant_df``) and calculates
    separate spectrograms for the sub-dataframes before versus after the
    large gap (see the ``time_delta_threshold`` parameter). If a
    sub-dataframe doesn't have enough rows for one full window
    (``len(df) < spectrogram_window_size``), it will be discarded and
    the corresponding features and spectrograms will not be returned.
    
    To calculate spectrograms on smaller inconsistencies in the sampling
    rate, e.g. 1 second versus 5 second delta between consecutive
    observations, this function calculates one spectrogram that
    *assumes* a constant sampling rate. For Strong-D data, the assumed
    constant *steps* sampling rate is 1 sample per minute (majority time
    delta between consecutive steps observations) and the assumed
    constant *HR* sampling rate is 1 sample per 9 seconds (mean time
    delta between consecutive HR observations).

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
    :spectrogram_overlap_size: number of samples to overlap/re-use 
        between consecutive windowed Fourier transforms within the
        spectrogram. This corresponds to the ``noverlap`` parameter in
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

    # one-sided spectrogram
    get_spectrogram = lambda x: signal.spectrogram(
        x,
        fs=spectrogram_samples_per_sec,
        nperseg=spectrogram_window_size,
        noverlap=spectrogram_overlap_size,
        mode="magnitude",
    )
    # num freq bands = nperseg/2 + 1

    # keep only groups with enough rows for >=1 full window
    filtered_df = participant_df.groupby("group").filter(
        lambda g: len(g) >= spectrogram_window_size
    )

    # create a spectrogram for each group (where the time delta is under
    # time_delta_threshold within each group)
    spectrograms = filtered_df.groupby("group")[spectrogram_col].apply(get_spectrogram)

    # reshape the spectrograms into dataframes (indexed by time), where
    # each frequency band is its own field/column
    features_list = []
    for i in spectrograms.index:
        # extract the frequency, time and spectrogram values
        (f, t, Sxx) = spectrograms.loc[i]

        # retrieve the original timestamps
        time = filtered_df.groupby("group").get_group(i).index[0] + pd.to_timedelta(
            t, unit="s"
        )

        # reshape the spectrogram into a dataframe, where time becomes
        # the index and each frequency band becomes a column
        features_list.append(
            pd.DataFrame(
                data=Sxx.T,
                index=time,
                columns=[
                    "spectrogram_" + str(np.round(f[j], 5)) + "Hz"
                    for j in range(len(f))
                ],
            )
        )

    features_df = pd.concat(features_list)

    return (features_df, spectrograms)


if __name__ == "__main__":
    main()
