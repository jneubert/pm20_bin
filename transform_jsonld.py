# nbt, 2021-04-20
#
# uses PyLD for transformation, which includes labels in the framed result

from pyld import jsonld
import json
import sys

# get the frame name as command line argument
# referenced context file has to be pulled in via http/s url
frame_fh = open('../web/schema/' + sys.argv[1] + '.jsonld').read()
frame = json.loads(frame_fh)

data_fh = open('../data/rdf/pm20.interim.jsonld').read()
data = json.loads(data_fh)

#result = jsonld.flatten(data)
result = jsonld.frame(data, frame)

print(json.dumps(result, indent=2))

