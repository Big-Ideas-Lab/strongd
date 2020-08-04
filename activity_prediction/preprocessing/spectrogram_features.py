import pandas as pd
import numpy as np
from scipy import signal
from tqdm import tqdm
import pickle

import matplotlib.pyplot as plt
import plotly.express as px

# TODO: docs
def get_participant_spectrograms(participant_df, time_delta_threshold, spectrogram_col, spectrogram_samples_per_sec, spectrogram_window_size):
    """Get spectrograms for a single participant
    
    :param participant_df: pandas dataframe indexed on a datetime column. This contains data for a _single_ participant and contains the column specified in the parameter `spectrogram_col`.
    :param time_delta_threshold: pandas date offset. If two consecutive timestamps T1 and T2 in participant_df have `(T2 - T1) > time_delta_threshold`, then separate spectrograms will be returned for observations preceding (and including) T1 and observations following (and including) T2.
    """
    
    # assert that the dataframe is sorted on its index (time)
    assert all(participant_df.index == participant_df.index.sort_values())
    
    # find the time deltas between consecutive time stamps
    deltas = [participant_df.index[i+1] - participant_df.index[i] for i in range(len(participant_df.index) - 1)]
    
    # always include the 1st data point
    participant_df['deltas'] = [pd.Timedelta('0')] + deltas
    participant_df[participant_df.deltas > time_delta_threshold]
    
    # if there exists time deltas greater than time_delta_threshold, then 
    # assign groups to each "chunk" of time ranges that don't exceed time_delta_threshold
    if any(participant_df.deltas > time_delta_threshold):
        indices = participant_df[participant_df.deltas > time_delta_threshold].index
        participant_df['group'] = 0
        for i in range(len(indices)):
            if i == len(indices) - 1:
                participant_df.loc[indices[i]:, 'group'] = i+1
                continue

            participant_df.loc[indices[i]:indices[i+1], 'group'].iloc[:-1] = i+1  # iloc[:-1] makes the endpoint noninclusive

    participant_df['group'] = participant_df['group'].astype('category')
    
    # one-sided spectrogram
    get_spectrogram = lambda x: signal.spectrogram(x, fs=spectrogram_samples_per_sec, nperseg=spectrogram_window_size, noverlap=None, mode='magnitude')
    # num freq bands = nperseg/2 + 1
    
    # create a spectrogram for each group, where the time delta is under time_delta_threshold within each group
    spectrograms = participant_df.groupby('group')[spectrogram_col].apply(get_spectrogram)
    
    return spectrograms
    