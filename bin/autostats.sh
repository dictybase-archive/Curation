#!/bin/bash

perl update_stats.pl -d=../db/stats.db -c=../conf/$MODE.yml && perl dump_stats.pl -d=../db/stats.db -c=../conf/$MODE.yml -o=../data/stats.xls
