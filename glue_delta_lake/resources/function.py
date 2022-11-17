import sys
import redshift_connector

if __name__ == "__main__":
    conn = redshift_connector.connect(
        user="awsuser",
        password="R3dsh1ft",
        host="grh-sandbox-redshift-cluster.c3cjlschgeym.ca-central-1.redshift.amazonaws.com",
        database="dev",
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
