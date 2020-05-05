# 03_c_quantification.R
# This file back-models carbon to historical areas of mangrove extent in Thailand.

#-----------------------------------
# Conceptual steps

# Back-modeling of carbon to historical mangroves areas in Thailand
# Steps:
#  1. Load in data
#     a. SOC data - Sanderman et al.
#     b. Biomass data - Simard et al.
#     c. Chongwat data - ?
#  2. Identify ecologically meaningful regions for deriving averages
#     a. SOC k-means clustering to identify zones
#     b. Examine height data - how best to do this?
#  3. Summarize data by chongwat
#  4. Map average values onto map
#     a. By ecological zone
#     b. By chongwat

#-----------------------------------

print("Begin Step 3. backmodeling of carbon stocks to historical mangrove extent...")

#-----------------------------------
# Load in libaries

library(cluster)
library(factoextra)
library(gdalUtils)
library(NbClust)
library(raster)
library(rgdal)
library(sf)
library(sp)
library(spsurvey)
library(tidyverse)

#---------------------------------
# define directories

raw_dir <- "./data/raw/"
in_dir <- "./data/processed/"
scratch_dir <- "./data/scratch/"
#out_dir <- "./data/processed/"

#--------------------------------

#######################
## SOC Back-modeling ##
#######################

#---------------------------------
# SOC data - k-means clustering analysis
# Load in necessary data

chngwts <- read_sf(paste0(in_dir, "cstl_prvncs/cstl_prvncs.shp"))
soc <- raster(paste0(raw_dir, "rasters/Mangrove_soc_Thailand.tif"))
agb <- raster(paste0(raw_dir, "rasters/Mangrove_agb_Thailand.tif"))

#--------------------------------
# Derive average soc and biomass values for each chongwat

# Or should it be median values?

chngwts$ADM1_ID <- 1:nrow(chngwts)
chngwts <- dplyr::select(chngwts, ADM1_EN, ADM1_ID, geometry)
chngwts_sp <- as(chngwts, "Spatial")

soc_empty <- raster(nrows=32000, ncols=24000)
extent(soc_empty) <- extent(soc)
projection(soc_empty) <- CRS("+proj=longlat +datum=WGS84 +no_defs +ellps=WGS84 +towgs84=0,0,0")
values(soc_empty) <- NA

chngwt_avgs <- data.frame("ADM1_ID" = 1:nrow(chngwts_sp), 
                      "SOC_AVG" = NA, "SOC_SD" = NA,
                      "AGB_AVG" = NA, "AGB_SD" = NA)

for(i in 1:nrow(chngwts_sp)) {
  
  shp <- chngwts_sp[i, ]
  chngwt <- shp$ADM1_EN
  
  soc_crop <- crop(soc, shp)
  soc_dat <- raster::extract(soc_crop, shp, df = T)
  chngwt_avgs$SOC_AVG[i] <- mean(soc_dat$Mangrove_soc_Thailand, na.rm = T)
  chngwt_avgs$SOC_SD[i] <- sd(soc_dat$Mangrove_soc_Thailand, na.rm = T)
  
  rm(soc_dat, soc_crop)
  gc()

}

for(i in 1:nrow(chngwts_sp)) {
  
  shp <- chngwts_sp[i, ]
  chngwt <- shp$ADM1_EN

  agb_crop <- crop(agb, shp)
  agb_dat <- raster::extract(agb_crop, shp, df = T)
  chngwt_avgs$AGB_AVG[i] <- mean(agb_dat$Mangrove_agb_Thailand, na.rm = T)
  chngwt_avgs$AGB_SD[i] <- sd(agb_dat$Mangrove_agb_Thailand, na.rm = T)

  rm(agb_crop, agb_dat)
  gc()
  
}

chngwts_c <- chngwts_sp %>% 
  st_as_sf() %>%
  left_join(chngwt_avgs, by = "ADM1_ID")

st_write(chngwts_c, dsn = paste0(in_dir, "chngwts_c"), driver="ESRI Shapefile")

rm(chngwts_sp, agb, soc, shp)

#-------------------------------------------
# Intersect the provinces C data with historic mangrove extent

crs102028 <- "+proj=aea +lat_1=7 +lat_2=-32 +lat_0=-15 +lon_0=125 +x_0=0 +y_0=0 +datum=WGS84 +units=m +no_defs"

mg_historic <- st_read(paste0(in_dir, "shapefiles/dissolved_102028.shp"))
mg_2000 <- st_read(paste0(in_dir, "shapefiles/mg2000_102028.shp"))
mg_2014 <- st_read(paste0(in_dir, "shapefiles/mg2014_102028.shp"))

chngwts_c_102028 <- chngwts_c %>%
  st_transform(crs102028)

mg_hstrc_chngwts <- st_intersection(chngwts_c_102028, mg_historic)










# Union and buffer the chongwats by 10 km 

albersSEAsia <- CRS(" +proj=aea +lat_1=7 +lat_2=-32 +lat_0=-15 +lon_0=125 +x_0=0 +y_0=0 +datum=WGS84 +units=m +no_defs ")
epsg4326 <- CRS(" +proj=longlat +ellps=WGS84 +datum=WGS84 +no_defs ")

cngwt <- st_read("./data/processed/cstl_prvncs")

cngwt_union <- st_union(cngwt) %>%
  st_transform(crs = albersSEAsia)

cngwt_bffr <- st_buffer(cngwt_union, 5000) %>%
  st_transform(crs = epsg4326)

adm0 <- read_sf("./data/raw/tha_admbnda_adm0_rtsd_20190221.shp")
sea_adm0 <- read_sf("./data/raw/se_asia.shp")

# Geomorphology data

tsm <- raster("../../ch1_c_estimation/analysis/data/raw/site_map/tha_mean_tsm.tif")
tdl <- raster("../../ch1_c_estimation/analysis/data/raw/site_map/m2_4326_a.tif")

tdl_new <- resample(tdl, tsm, method = "bilinear")

gmrphStack <- stack(tsm, tdl_new)

gmrphStackMskd <- mask(gmrphStack, as(cngwt_bffr, "Spatial"))

gmrph_dat <- raster::extract(gmrphStack, as(cngwt_bffr, "Spatial"), cellnumbers = T) %>%
  as.data.frame()  %>%
  rename(tsm = "tha_mean_tsm",
         tdl = "m2_4326_a",
         id = "cell")

# Identify optimal number of clusters using "elbow" method

maxClstrs <- 20

optClstrs <- data.frame(clstrs = seq(1, maxClstrs, 1),
                        tot_wss = NA)

for(i in 1:maxClstrs) {
  
  kmeansClass <- kmeans(na.omit(gmrph_dat[ , c(2, 3)]), i, nstart = 30)
  optClstrs$tot_wss[i] <- kmeansClass$tot.withinss
  
}

fviz_nbclust(na.omit(gmrph_dat[, c(2,3)]), kmeans, method = 'wss', k.max = 25, nstart = 30)
fviz_nbclust(na.omit(gmrph_dat[, c(2,3)]), kmeans, method = 'silhouette', k.max = 25, nstart = 30)

plot(optClstrs)

# Classify coastline based on optimal number of clusters

idx <- na.omit(gmrph_dat[ , c(1, 2, 3)])

kmeansClass <- kmeans(na.omit(gmrph_dat[ , c(2, 3)]), 4, nstart = 30)

idx <- cbind(idx, kmeansClass$cluster)

classed_dat <- gmrph_dat %>%
  left_join(idx, by = c("id")) %>%
  rename(class = "kmeansClass$cluster") %>%
  rename(tsm = "tsm.x",
         tdl = "tdl.x") %>%
  dplyr::select(id, tsm, tdl, class)

classes <- gmrphStack[[1]]

values(classes) <- 0

dat <- values(classes)

vals <- dat %>%
  as.data.frame() %>%
  mutate(id = row_number()) %>%
  left_join(classed_dat, by = "id") %>%
  pull(class)


values(classes) <- vals
classesCrpd <- crop(classes, as(cngwt_bffr, "Spatial"))
classesMskd <- mask(classesCrpd, as(cngwt_bffr, "Spatial"))

classesMskd_df <- as.data.frame(classesMskd, xy = T, na.rm = T)

ggplot(sea_adm0) +
  geom_sf(fill = "#F2F2F2") +
  geom_sf(data = adm0, aes(geometry = geometry), fill = "#E5E5E5") +
  geom_raster(data = classesMskd_df, aes(x = x, y = y, fill = factor(tha_mean_tsm))) +
  theme_bw() +
  xlab("") +
  ylab("") +
  labs(fill = "Cluster") +
  xlim(c(98, 105)) +
  ylim(c(5, 15)) +
  ggtitle("no. clusters = 4") +
  theme(legend.position = "bottom")


# Stratify height data

library(BAMMtools)   # For Jenks Breaks

simard_agb <- raster("../../ch1_c_estimation/analysis/data/raw/modeled_datasets/Mangrove_agb_Thailand.tif")
simard_height <- raster("~/Desktop/mangrove_c_model_data/CMS_Global_Map_Mangrove_Canopy_1665/data/Mangrove_hmax95_Thailand.tif")

hgt_resample <- raster(nrow = 28062/3, ncol = 20575/3, crs = epsg4326, ext = extent(simard_height))

simard_height_rsmpl <- resample(simard_height, hgt_resample, method = "bilinear")


# For height
m_hgt <- c(0.5, 8.5, 1, 8.5, 15.3, 2, 15.3, 22.1, 3)
rclmat_hgt <- matrix(m_hgt, ncol = 3, byrow = T)
rc <- reclassify(simard_height, rclmat_hgt)

# For biomass
m <- c(57, 99, 1, 99, 139, 2, 139, 185, 3)
rclmat <- matrix(m, ncol = 3, byrow = T)
rc <- reclassify(simard_agb, rclmat)

simard_height_df_rs <- as.data.frame(simard_height_rsmpl, xy = T, na.rm = T)
colnames(simard_height_df_rs) <- c("hgt", "x", "y")

simard_height_df <- as.data.frame(simard_height, xy = T, na.rm = T)
colnames(simard_height_df) <- c("hgt", "x", "y")

getJenksBreaks(simard_height_df$hgt, 5)

#0.8485  6.7880 11.8790 16.9700 22.0610

ggplot(simard_height_df, aes(hgt)) +
  geom_histogram(bins = 20) +
  theme_bw() +
  xlab("Mean mangrove canopy height, 30 x 30 m (m)") +
  ylab("Count")

ggplot(sea_adm0) +
  geom_sf(fill = "#F2F2F2") +
  geom_sf(data = adm0, aes(geometry = geometry), fill = "#E5E5E5") +
  geom_raster(data = simard_height_df, aes(x = x, y = y, fill = hgt)) +
  theme_bw() +
  xlab("") +
  ylab("") +
  labs(fill = "Cluster") +
  #coord_sf(xlim = c(99.85, 100.05), ylim = c(13.2, 13.4)) +
  xlim(c(99.85, 100.05)) +
  ylim(c(13.2, 13.4)) +
  ggtitle("no. clusters = 4") +
  theme(legend.position = "bottom")



