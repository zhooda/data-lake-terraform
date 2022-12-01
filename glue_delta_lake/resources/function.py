import sys
import redshift_connector

try:
    from awsglue.context import GlueContext
    from awsglue.dynamicframe import DynamicFrame
    from awsglue.job import Job
    from awsglue.utils import getResolvedOptions

    # from awsglue.transforms import *
except ImportError:
    raise ImportError("Please run script in a Glue job to import Glue libraries")
    # pass

GLUE_CUSTOM_PARAMS = ["username", "password", "database", "cluster"]

# TODO: Modify to support sending alerts if a data source should not include deletes


def validate_custom_params(args):
    """Validate custom parameters for Glue job"""
    if not all(["--" + param in sys.argv for param in args]):
        raise ValueError(
            "Missing required parameters. Please check your Glue job configuration.",
            f"Expected parameters: {args}, got: {sys.argv}",
        )

    return getResolvedOptions(sys.argv, ["JOB_NAME", *args])


if __name__ == "__main__":
    args = validate_custom_params(GLUE_CUSTOM_PARAMS)

    conn = redshift_connector.connect(
        user=args.get("username", "awsuser"),
        password=args.get("password", ""),
        host=args.get(
            "cluster",
            "grh-sandbox-redshift-cluster.c3cjlschgeym.ca-central-1.redshift.amazonaws.com",
        ),
        database=args.get("database", "dev"),
    )

    query = """
    create external schema spectrum_schema from data catalog
    database 'delta-lake'
    iam_role 'arn:aws:iam::037182765867:role/service-role/AmazonRedshift-CommandsAccessRole-20221117T065213'
    create external database if not exists;
    """

    conn.autocommit = True
    r = conn.run("drop schema if exists spectrum_schema cascade;")
    r = conn.run(query)
