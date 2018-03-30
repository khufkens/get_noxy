# Combines geopunt.be points of interest and IRCELINE NOx data

# The code uses base R, it could be a bit shorter
# using tidyverse semantics but this increases library requirements
# and decreases the educational value of the code due to non standard coding
# style (pipes).

# data processing
library(jsonlite)
library(rgdal)
library(raster)

# plotting
library(ggplot2)
library(ggthemes)

# legend picture of colour and concentration values for reference
# http://www.irceline.be/air/legend/no2_anmean_NL.svg

#---- grab meta data for points of interest in geopunt.be

#list all points of interest in the geopunt.be API
all_poi <- jsonlite::fromJSON("http://poi.api.geopunt.be/v1/core/poitypes")

# list all school categories used in the example
education <-all_poi$categories$term[grepl("onderwijs",
                                          tolower(all_poi$categories$term))]

# an example on how to query all sport categories
sport <-all_poi$categories$term[grepl("sport",
                                      tolower(all_poi$categories$term))]

# function to get point of interest data using search
# terms listed by the API
poi_location <- function(poi_term = "GewoonLagerOnderwijs"){
  
  # query the poi term
  poi_data <- jsonlite::fromJSON(sprintf("http://poi.api.geopunt.be/v1/core?poitype=%s",
                                         poi_term))
  
  # sanity check, if no data is there, skip
  if(length(poi_data$pois)==0){
    return(NULL)
  }
  
  # convert the point location data to a more appealing format
  lat_lon <- do.call("rbind", lapply(poi_data$pois$location$points, function(x){
    coordinates <- unlist(x$Point$coordinates)
    if(length(coordinates) > 1){
      return(data.frame(lat = coordinates[2],
                        lon = coordinates[1]))
    } else {
      return(data.frame(lat = NULL,
                        lon = NULL))
    }
  }))
  
  # get categories, drop first "Type" column, do the same for the labels
  categories <- do.call("rbind",
                        poi_data$pois$categories)[-1]
  labels <- do.call("rbind",
                    poi_data$pois$labels)[-1]
  
  # stuff into output data frame and rename columns
  df <- data.frame(labels, categories, lat_lon)
  colnames(df) <- c("school_name",
                    "poi_term",
                    "type",
                    "lat",
                    "lon")
  
  # return values
  return(df)
}

# extract all data poi meta-data for a nested list of poi
poi_subset = do.call("rbind", lapply(education, function(x){
  output <- try(poi_location(x))
  if(inherits(output,"try-error")){
    return(NULL)
  } else {
    return(output)
  }
}))

#---- grab matching NOX data using from the IRCELINE WMS server

# Function to grab data from a WMS server using a colour lookup table.
# Given that the data is visible this falls within fair use in my book.
# The function can be used on all IRCLINE data streams provided that
# use the proper wms server and layer settings. This would for example
# allow you to query PM2.5 or PM10 data in addition to (yearly) NOx values.
get_nox <- function(lat,
                    lon,
                    wms_server = "http://geo.irceline.be/rioifdm/wms",
                    wms_layer = "rioifdm:no2_anmean_2016_ospm_vl"){
  
  # create a look up table to match colour values
  # with a particular NOx concentration using a
  # minimum distance approach (see below)
  LUT <- as.data.frame(matrix(c(0, 0, 255, 10,
                                0, 150, 255, 15,
                                0, 155, 0, 20,
                                0, 255, 0, 25,
                                255, 255, 0, 30,
                                255, 188, 0, 35,
                                255, 102, 0, 40,
                                255, 0, 0, 45,
                                155, 0, 0, 50,
                                103, 0, 0, 55),
                              10,
                              4,
                              byrow = TRUE))
  
  # add column names
  colnames(LUT) <- c("r","g","b","nox_value")
  
  # the offset for the bounding box of the wms query
  # is hard coded at 2 m converted to degrees
  offset <- (0.00001/1.1132) * 2
  
  # create xml scheme to query WMS data using GDAL
  wms_description <- paste0('<GDAL_WMS>
                            <Service name="WMS">
                            <Version>1</Version>
                            <ServerUrl>',wms_server,'?</ServerUrl>
                            <Layers>',wms_layer,'</Layers>
                            <ImageFormat>image/png</ImageFormat>
                            </Service>
                            <DataWindow>
                            <UpperLeftX>',lon - offset,'</UpperLeftX>
                            <UpperLeftY>',lat + offset,'</UpperLeftY>
                            <LowerRightX>',lon + offset,'</LowerRightX>
                            <LowerRightY>',lat - offset,'</LowerRightY>
                            <SizeX>3</SizeX>
                            <SizeY>3</SizeY>
                            </DataWindow>
                            <Projection>EPSG:4326</Projection>
                            <BlockSizeX>1024</BlockSizeX>
                            <BlockSizeY>1024</BlockSizeY>
                            <OverviewCount>7</OverviewCount>
                            </GDAL_WMS>')
  
  # query data and stuff in convenient raster stack
  r <- try(raster::stack(rgdal::readGDAL(wms_description,
                                         silent = TRUE)))
  
  # trap server errors (edge cases?), return NA
  if(inherits(r,"try-error")){
    return(NA)
  }
  
  # Grab the colour values at the exact location within the
  # downloaded bounding box, you can use a buffer argument to
  # summarize these values (mean / median) to get an idea of
  # surroundings of a location, rather than its absolute location.
  values <- raster::extract(r, SpatialPoints(cbind(lon, lat),
                                             sp::CRS("+init=epsg:4326")))
  
  # calculate colour distance (vector sum)
  distance = apply(LUT[,1:3],1, function(x){
    sqrt(
      sum((x - values)^2)
    )
  })
  
  # return colour information as the upper boundary of the
  # concentration interval using the minimum distance per
  # look up table (this aproach is necessary as colour information
  # is not absolute -> PNG / JPEG information loss in WMS scarping)
  LUT$nox_value[which(distance == min(distance))]
}

# create a simple progress bar for ease of mind while downloading
pb <- txtProgressBar(min = 0, max = nrow(poi_subset), style = 3)
i <- 0

# loop over all meta-data locations and grab NOx concentrations
# in this case limited to all education (onderwijs) institutions
# in the geopunt.be points of interest database
poi_subset$nox_value = unlist(apply(poi_subset, 1, function(x){
  setTxtProgressBar(pb, i)
  i <<- i + 1
  Sys.sleep(0.1)
  get_nox(lat = as.numeric(x['lat']),
          lon = as.numeric(x['lon']))
}))

# clean up the progress bar
rm(i)
close(pb)

# create facet plot (cummulatie distributions in this case of
# all school types) / might need a correction for the
# qualitative binning beforehand 
facet = ggplot(data = poi_subset, aes(nox_value)) + 
  stat_ecdf() +
  xlab("NOx value (µg/m³)") +
  ylab("Cummulative Probablity") +
  facet_wrap(~ type, ncol = 4) +
  theme_minimal()

pdf("~/nox_facet_plot.pdf",12,9)
plot(facet)
dev.off()