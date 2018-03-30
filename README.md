# Combines geopunt.be points of interest and IRCELINE NOx data

get_noxy.r, wordplay on moxy: n. When someone has guts or balls, they have moxy.

## air quality download scripts

The script uses the [geopunt.be](http://geopunt.be) API to download a list of point of interest descriptors. These descriptors are then used to list all of the underlying points of interest (schools in the example). Descriptors are searched for using regular expressions and grep from the overall list.

A second function uses the GDAL spatial libraries to read the WMS data from IRCELINE servers which provide data on air quality, for the points of interest.

Data are finally plotted as a cummulative distribution facet plot using the type parameter (which kind of school in the example) as a grouping factor.

![](https://github.com/khufkens/get_noxy/raw/master/nox_facet_plot.png) 