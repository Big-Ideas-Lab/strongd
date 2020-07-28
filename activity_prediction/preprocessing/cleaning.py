import pandas as pd
import os
from tqdm import tqdm
import pickle
import click

@click.command()
@click.option('--fitabase_export_dir', help='Path to the directory containing Fitbit data exported via Fitabase.')
@click.option('--save_dir', help='Path to the directory for saving the cleaned Fitabase/Fitbit data.')

def main(fitabase_export_dir, save_dir):
    """Clean and save HR (seconds) and steps (minutes) data exported from Fitabase/Fitbit."""
    
    # find only HR (seconds) and steps (minutes) files
    steps_hr_files = [f for f in os.listdir(fitabase_export_dir) if os.path.isfile(os.path.join(fitabase_export_dir, f)) and (('minuteStepsNarrow' in f) or ('heartrate_seconds' in f))]
    steps_file_list = [f for f in steps_hr_files if 'minuteStepsNarrow' in f]
    hr_file_list = [f for f in steps_hr_files if 'heartrate_seconds' in f]
    
    print("Steps:")
    steps_df = clean(export_dir=fitabase_export_dir, 
                     file_list=steps_file_list, 
                     datetime_col='ActivityMinute',
                     save_path=os.path.join(save_dir, 'steps_minutes_df.pickle'))
    print("Saved steps data.")
    
    print("HR:")
    hr_df = clean(export_dir=fitabase_export_dir, 
                  file_list=hr_file_list, 
                  datetime_col='Time',
                  save_path=os.path.join(save_dir, 'hr_seconds_df.pickle'))
    print("Saved HR data.")

def clean(export_dir, file_list, datetime_col, save_path):
    """Clean exported Fitabase/Fitbit data
    
    This function reads exported Fitabase files as dataframes, concatenates these dataframes and cleans the resulting concatenated dataframe.
    
    :param export_dir: full path to directory containing exported Fitabase files
    :param file_list: list of filenames (nested under export_dir) to be concatenated and cleaned into one dataframe. Each file has the format <participant ID>_<data description>_<start date>_<end date>.csv, e.g. "32113-0004_heartrate_seconds_20161201_20200131.csv"
    :param datetime_col: name of column containing datetime values
    :param save_path: full path for saving the concatenated and cleaned dataframe as a pickle
    :returns: the concatenated and cleaned dataframe
    """
    
    # concatenate all participants, index on participant and time
    id_data_dict = dict()
    
    print("Concatenating.")
    for f in tqdm(file_list):
        participant_id = f.split('_')[0]
        path = os.path.join(export_dir, f)
        df = pd.read_csv(path)
        id_data_dict[participant_id] = df

    concat_df = pd.concat(id_data_dict)
    
    print("Converting to datetime format.")
    # convert to datetime type
    concat_df[datetime_col] = pd.to_datetime(concat_df[datetime_col], format='%m/%d/%Y %I:%M:%S %p')

    print("Reindexing.")
    # reindex to (id, datetime)
    concat_df.reset_index(inplace = True)
    concat_df.rename(columns={'level_0': 'Id'}, inplace=True)
    concat_df.set_index(['Id', datetime_col], inplace=True)
    concat_df.drop(columns='level_1', inplace=True)

    # just in case, drop duplicates in the index
    concat_df.index.drop_duplicates()
    
    print("Saving.")
    # save
    with open(save_path, 'wb') as f:
        pickle.dump(concat_df, f)
        
    return concat_df

if __name__ == "__main__":
    main()
