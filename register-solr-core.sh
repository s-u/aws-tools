#!/bin/bash 

# Quick and easy way to setup Apache Solr for RCloud Search

SOLR_DATA="$1"

if [ -z "$SOLR_DATA" ]; then
    echo ""
    echo "ERROR: please specify destination data directory"
    echo ""
    echo " Usage: $0 <destination>"
    echo ""
    exit 1
fi

if [ ! -e schema.xml ]; then
    echo ""
    echo "ERROR: this script must be run from the conf/solr directory"
    echo ""
    exit 1
fi

WD="`pwd`"
INSTANCEDIR="${SOLR_DATA}/rcloudnotebooks"
DATADIR="${INSTANCEDIR}/data"
CONFDIR="${INSTANCEDIR}/conf"

#cp -R solr/example/solr/collection1/ solr/example/solr/rcloudnotebooks
mkdir -p $DATADIR
mkdir -p $CONFDIR

cp "$WD/solr.xml" ${SOLR_DATA}/
cp "$WD/schema.xml" ${CONFDIR}/
cp "$WD/solrconfig.xml" ${CONFDIR}/
cp "$WD/word-delim-types.txt" ${CONFDIR}/
cp "$WD/code-delim-types.txt" ${CONFDIR}/
cp  "$WD/synonyms.txt" ${CONFDIR}/
cp  "$WD/elevate.xml" ${CONFDIR}/
cp  "$WD/stopwords.txt" ${CONFDIR}/
cp -r "$WD/lang" ${CONFDIR}/
# Create a collection for the RCloud Notebooks


QUERY="http://localhost:8983/solr/admin/cores?action=CREATE&name=rcloudnotebooks&instanceDir=$INSTANCEDIR&config=solrconfig.xml&schema=schema.xml&dataDir=$DATADIR"
echo curl "'$QUERY'"
