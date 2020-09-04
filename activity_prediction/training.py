import pandas as pd
import numpy as np
import pickle
import random
import json
import click

random.seed(0)

from sklearn.ensemble import RandomForestClassifier
from sklearn.model_selection import GridSearchCV
from sklearn.model_selection import LeaveOneGroupOut

# random forest parameter values to test in the grid search
PARAM_GRID = {
    "max_features": ["sqrt", None, 0.2, 0.4, 0.8],
    "min_samples_leaf": [1, 10, 100, 1000],
    "max_samples": [None, 0.2, 0.4, 0.8],
}


@click.command()
@click.option(
    "--merged_features_path",
    help="Path to the pickle file containing the merged dataframe with all features to use for model training.",
)
@click.option(
    "--save_path", help="Path for saving the grid search results as a pickle file.",
)
@click.option("--binary/--not-binary")  # TODO
# TODO: docs
def main(merged_features_path, save_path, binary):
    """Train and select the best random forest on the feature set in the
    input file

    :param merged_features_path: path to pickle file containing a pandas
        dataframe with features and labels. This dataframe must have
        indices ("Id", "Time").    
    :param save_path: [description]
    """
    with open(merged_features_path, "rb") as f:
        X = pickle.load(f)

    # train-test split
    with open("train_test_participants.json") as f:
        split_dict = json.load(f)

    if binary:  # only classify strength vs aerobic
        X = X[X["Arm"].isin(["aerobic", "strength"])]

    # re-index and separate features X vs labels y
    X.drop(["Steps", "Value"], axis=1, inplace=True, errors="ignore")

    start_nrows = X.shape[0]
    print(f"The input (binary={binary}) has {start_nrows} rows.")
    X.dropna(inplace=True)

    end_nrows = X.shape[0]
    if end_nrows < start_nrows:
        print(f"Dropped {start_nrows - end_nrows} rows with NAs.")

    y = X["Arm"]
    X.drop("Arm", axis=1, inplace=True)

    # only use training participants that exist in the data
    split_dict["train"] = list(
        set(split_dict["train"]) & set(X.index.get_level_values(0).unique())
    )

    print(
        f"Training on the following {len(split_dict['train'])} participants: {split_dict['train']}"
    )

    # get training data
    X_train = X.loc[split_dict["train"]]
    y_train = y.loc[split_dict["train"]]

    # perform grid search
    grid_search = grouped_grid_search(X_train, y_train, PARAM_GRID)

    with open(save_path, "wb") as f:
        pickle.dump(grid_search, f)
    print(f"Saved the grid search results to {save_path}.")


def grouped_grid_search(X, y, param_grid):
    """Perform a grid search over random forest parameters using grouped
    leave one out cross-validation (LOOCV)

    The *grouped* LOOCV ensures that within a single CV split, one
    group's data (i.e. one participant's data) exist only within the
    training fold or the validation fold but not both.

    The best combination of parameter values is determined by
    scikit-learn's "f1-macro" score. See
    https://scikit-learn.org/stable/modules/generated/sklearn.metrics.f1_score.html.

    :param X: [description]
    :param y: [description]
    :param param_grid: [description]
    :returns: [description]
    """

    # cross validation iterator for grouped data
    # in this case, each participant ID (in the first index) is a group
    groups = list(X.index.get_level_values(0))

    # leave one person out cross validation
    logo = LeaveOneGroupOut()

    # random forest and grid
    rf = RandomForestClassifier(
        n_estimators=1000,
        criterion="gini",
        bootstrap=True,
        oob_score=True,
        n_jobs=-1,
        random_state=0,
        verbose=1,
    )
    grid_search = GridSearchCV(
        estimator=rf,
        param_grid=param_grid,
        scoring="f1_macro",
        n_jobs=-1,
        cv=logo,
        verbose=1,
    )

    grid_search.fit(X, y, groups=groups)

    return grid_search


if __name__ == "__main__":
    main()
