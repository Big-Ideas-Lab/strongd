## Order of Preprocessing
Run the scripts in this directory in the following order:

1. `cleaning.py`
    * example usage: `python cleaning.py --fitabase_export_dir Export-1-31-2020_2_57_pm/ --save_dir clean_data/`
2. `spectrogram_features.py`
    * example usage: `python spectrogram_features.py --cleaned_steps_path clean_data/steps_minutes_df.pickle --cleaned_hr_path clean_data/hr_seconds_df.pickle --window_size_in_minutes 10 --no-overlap --save_dir features/`
3. `rolling_features.py`
    * example usage: `python rolling_features.py --cleaned_steps_path clean_data/steps_minutes_df.pickle --cleaned_hr_path clean_data/hr_seconds_df.pickle --window_size 10min --also_save_non_overlapping --save_dir features/`
4. `clean_labels.py`: `python clean_labels.py`
5. `merging.py`
    * example usage: `python merging.py --tolerance 1min features/steps_rolling_features_df_window=10min.pickle features/hr_rolling_features_df_window=10min.pickle features/merged/all_rolling_window=10min.pickle`

To see the documentation for any of the scripts above, run `python <script_name>.py --help` in your terminal.

Note: create the directories used for `save_dir` before running any of the commands above.

### `helperfuns.py`
This script contains various functions for loading, cleaning and plotting Strong-D data. You'll see that these functions are imported in many of the scripts above.