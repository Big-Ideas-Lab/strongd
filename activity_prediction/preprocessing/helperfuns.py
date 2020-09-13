import pandas as pd
import numpy as np
import pickle
import random

import matplotlib
import matplotlib.pyplot as plt
import matplotlib.dates as mdates
import plotly.graph_objects as go
import plotly.express as px
import seaborn as sns

sns.set_palette("colorblind")
plt.rcParams["font.family"] = "Times New Roman"
plt.rcParams["font.size"] = 14
plt.rcParams["axes.xmargin"] = 0
matplotlib.rcParams['axes.axisbelow'] = True
plt.rcParams['svg.fonttype'] = 'none'


def load_data(
    steps_path, hr_path, validate_ids=True, sample_num=None, subset_ids=None, sort=True
):
    """Load steps and HR data from pickle files

    :param steps_path: path to the pickle file containing a pandas
        dataframe of steps data with "Id" as the first index and
        "ActivityMinute" as the second (datetime) index.
    :param hr_path: path to the pickle file containing a pandas
        dataframe of HR data with "Id" as the first index and "Time" as
        the second (datetime) index.
    :param validate_ids: boolean that indicates whether to check that
        the steps and HR dataframes have the same set of values in their
        "Id" index, defaults to True.
    :param sort: boolean that indicates whether to sort the steps and HR
        dataframes by their first and second indices (in this order),
        defaults to True.
    :param sample_num: number of participants to sample for returning a
        subset of the steps and HR dataframes. Defaults to None, which
        will not perform any subsetting.
    :param subset_ids: list of participants IDs to choose for returning
        a subset of the steps and HR dataframes. These IDs should exist
        in the first "Id" index of these dataframes. Defaults to None,
        which will not perform any subsetting. ``sample_num`` takes
        precedence over this parameter.
    :returns: a tuple of two pandas dataframes: (steps_df, hr_df).
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
    elif subset_ids:
        print(
            f"Subsetting the steps and HR data to the participants specified in ``subset_ids``."
        )
        steps_df = steps_df.loc[subset_ids]
        hr_df = hr_df.loc[subset_ids]

    if sort:
        print("Sorting steps and HR data by participant ID and then timestamp.")
        steps_df.sort_index(level=["Id", "ActivityMinute"], inplace=True)
        hr_df.sort_index(level=["Id", "Time"], inplace=True)

    return (steps_df, hr_df)


def remove_zero_daily_steps(steps_df):
    """Remove all step data on a day if the total number of steps is
    zero on that day

    :steps_df: pandas dataframe containing a "Steps" (step count)
        column. The first index must be "Id" (participant ID) and the
        second index must be "ActivityMinute" (minute grain timestamps).
    :returns: pandas dataframe with rows removed
    """
    print(
        "Removing all step data on a day if the total number of steps is zero on that day."
    )

    # get date from the datetime index
    steps_df["date"] = steps_df.index.get_level_values(1).date

    # re-index on participant ID and date (not datetime)
    steps_df.reset_index(inplace=True)
    steps_df.set_index(["Id", "date"], inplace=True)

    # create an indexing mask to retain only days when the daily total number of steps is above zero
    daily_steps = steps_df.groupby(["Id", "date"]).Steps.sum()
    mask = daily_steps[daily_steps > 0].index
    steps_df = steps_df.loc[mask]

    # re-index back to the original index (Id, ActivityMinute)
    steps_df.reset_index(inplace=True)
    steps_df.set_index(["Id", "ActivityMinute"], inplace=True)

    # drop the date column
    steps_df.drop("date", axis=1, inplace=True)

    return steps_df


# PLOTTING
def plot_spectrogram(spectrogram, interactive=False, save_path=None):

    (f, t, Sxx) = spectrogram

    x_label = "Time (Seconds Elapsed)"
    y_label = "Frequency Band (Hz)"

    if interactive:
        fig = go.Figure(
            data=go.Heatmap(z=Sxx, x=t, y=f),
            layout=go.Layout(xaxis=dict(title=x_label), yaxis=dict(title=y_label)),
        )
        fig.show()
    else:
        # reshape
        spectrogram_df = pd.DataFrame(Sxx, index=np.round(f, 5), columns=t.astype(int))
        spectrogram_df.sort_index(ascending=False, inplace=True)
        ax = sns.heatmap(spectrogram_df, xticklabels = 300, cmap="Blues")
        ax.set(ylabel=y_label, xlabel=x_label)

        if save_path:
            plt.savefig(save_path, dpi=600, transparent=True)

        return ax


def plot_participant(
    df,
    participant_id,
    y_name,
    labels_df=None,
    label_offset=pd.Timedelta("10min"),
    label_duration=pd.Timedelta("1H"),
    interactive=False,
    x_name="Time",
    start_time=None,
    end_time=None,
    plot_other=False,
    save_path=None,
):

    participant_df = df.loc[participant_id]
    participant_labels = labels_df.loc[participant_id]

    if start_time and end_time:
        participant_df = participant_df.loc[start_time:end_time]
        participant_labels = participant_labels.loc[start_time:end_time]

    if not interactive:
        pd.options.plotting.backend = "matplotlib"

        ax = participant_df.plot()
        ax.set(ylabel=y_name, xlabel=x_name)

        if not (labels_df is None):
            for index, row in participant_labels.iterrows():
                ax.axvspan(
                    index + label_offset,
                    index + label_offset + label_duration,
                    color="tab:red",
                    alpha=0.3,
                )

                if plot_other:
                    ax.axvspan(
                        index - label_duration, index, color="tab:blue", alpha=0.3,
                    )

        if start_time and end_time:
            ax.xaxis.set_major_locator(mdates.HourLocator())
            ax.xaxis.set_major_formatter(mdates.DateFormatter("%H:00"))
            plt.setp(ax.get_xticklabels(), rotation=0, ha="center")

        ax.get_legend().remove()

        if save_path:
            plt.savefig(save_path, dpi=600, transparent=True)

        plt.show()
    else:
        prev_plotting_backend = pd.options.plotting.backend
        pd.options.plotting.backend = "plotly"
        fig = participant_df.plot()
        shapes = []
        if not (labels_df is None):
            for index, row in participant_labels.iterrows():
                shape = dict(
                    type="rect",
                    # x-reference is assigned to the x-values
                    xref="x",
                    # y-reference is assigned to the plot paper [0,1]
                    yref="paper",
                    x0=index + label_offset,
                    y0=0,
                    x1=index + label_offset + label_duration,
                    y1=1,
                    fillcolor="red",
                    opacity=0.3,
                    layer="below",
                    line_width=0,
                )
                shapes.append(shape)
                
                if plot_other:
                    shape = dict(
                        type="rect",
                        # x-reference is assigned to the x-values
                        xref="x",
                        # y-reference is assigned to the plot paper [0,1]
                        yref="paper",
                        x0=index - label_duration,
                        y0=0,
                        x1=index,
                        y1=1,
                        fillcolor="blue",
                        opacity=0.3,
                        layer="below",
                        line_width=0,
                    )
                    shapes.append(shape)

            fig.update_layout(
                shapes=shapes, xaxis_title=x_name, yaxis_title=y_name
            )

        fig.show()
        pd.options.plotting.backend = prev_plotting_backend
