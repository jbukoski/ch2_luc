# Spatial analyses for Ch 2.

library(tidyverse)
library(spsurvey)
library(sf)
library(raster)
library(rgdal)
library(sp)

#-----------------------------------
# Processing GMW mangrove extents

# Load in datasets 

adm0 <- read_sf("./data/raw/tha_admbnda_adm0_rtsd_20190221.shp")
adm1 <- readOGR("./data/raw/tha_admbnda_adm1_rtsd_20190221.shp")

mang1996 <- readOGR("./data/scratch/GMW_1996_buffered.shp")
mang2016 <- readOGR("./data/scratch/GMW_2016_buffered.shp")

#thai1 <- thai_1[thai_1$ADM1_EN %in% c("Krabi", "Trang"),]

intersection <- raster::intersect(adm1, mang2016)
intersection <- intersection[, c("FID", "ADM1_EN")]

intersection <- readOGR("./data/scratch/GMW_2016_intersection.shp")

albersSEAsia <- CRS(" +proj=aea +lat_1=7 +lat_2=-32 +lat_0=-15 +lon_0=125 +x_0=0 +y_0=0 +datum=WGS84 +units=m +no_defs ")

intersection_eqArea <- intersection %>%
  spTransform(albersSEAsia)

intersection_eqArea$area <- area(intersection_eqArea)

intersection_sf <- st_as_sf(intersection_eqArea)

areas <- intersection_sf %>% pull(area)

sum(areas) / 10000
    
intersection_tibble <- intersection_sf
st_geometry(intersection_tibble) <- NULL

intersection_tibble %>%
  group_by(ADM1_EN) %>%
  summarize(Area = sum(area) / 10000) %>%
  View()

st_write(intersection_sf, "./data/processed/GMW_2016_thai", "GMW_2016_thai", driver="ESRI Shapefile")

## Need to send back to BASH script to convert to raster

#--------------------------------------------------------
# Processing DMCR statistics data

rai1961 <- c(645000, 50625, 160000, 382500, 8750, 8125, 35000, 1446250, 191250, 358750, 28750, 335625, 243750, 288750)
rai1996 <- c(103570, 19698, 19586, 52601, 881, 3896, 6906, 830650, 120229, 190265, 9448, 176709, 150596, 183402)

has <- data.frame(cbind(rai1961, rai1996))*0.16

#----------------------------------------------
# Adjusting Chongwats by DMCR region


east <- c("Chanthaburi", "Rayong", "Trat")
central <- c("Bangkok", "Chachoengsao", "Chon Buri", "Phetchaburi", "Prachuap Khiri Khan", "Samut Prakan", "Samut Sakhon", "Samut Songkhram")
east_p <- c("Chumphon", "Nakhon Si Thammarat", "Pattani", "Phatthalung", "Songkhla", "Surat Thani")
west_p <- c("Krabi", "Phangnga", "Phuket", "Ranong", "Satun", "Trang")

cngwt <- read_sf("./data/raw/tha_admbnda_adm1_rtsd_20190221.shp") %>%
  mutate(region = ifelse(ADM1_EN %in% east, "east", 
                         ifelse(ADM1_EN %in% central, "central",
                                ifelse(ADM1_EN %in% east_p, "eastern peninsula",
                                       ifelse(ADM1_EN %in% west_p, "western peninsula", NA))))) %>% 
  dplyr::select(ADM1_EN, region) %>%
  filter(!is.na(region))

# Placeholder figure

plot(adm0[1]$geometry, col="white", axes=T)
plot(cngwt[1]$geometry, col=as.factor(cngwt$region), add = T)
legend("bottomright", 
       legend=c("Central", "East", "East Peninsula", "West Peninsula"),
       fill =c(1,2,3,4),
       col=c(1, 2, 3, 4))
  
st_write(cngwt, "./data/processed/cstl_prvncs", "cstl_prvncs", driver="ESRI Shapefile")


#------------------------------------------------
# K means clustering of height and soil
# Simard biomass
#  minimum: 57.410; maximum: 185.918
# Simard height
#  minimum: 0.849; maximum: 22.061

library(cluster)
library(NbClust)
library(factoextra)

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



#--------------------------------------------------
# Produce land use change map for central region (i.e., BKK)

suppressMessages(library(grid))
suppressMessages(library(ggmap))
suppressMessages(library(rasterVis))
suppressMessages(library(rnaturalearth))
suppressMessages(library(rnaturalearthdata))

thai1996 <- raster("./data/processed/GMW_1996_thai.tif")   # value = 1
thai2016 <- raster("./data/processed/GMW_2016_thai.tif")   # value = 2
gmw_luc <- raster("./data/processed/gmw_luc.tif")          # loss = 1, gain = 2, no change = 3

world <- ne_countries(scale = "medium", returnclass = "sf")

e <- extent(99.5, 101.5, 12.8, 13.8)
luc_centro <- crop(gmw_luc, e)

luc_df <- as.data.frame(luc_centro, na.rm = T, xy = T) %>%
  rename(y = "gmw_luc", x = "x", value = "2") %>%
  mutate(col = ifelse(value == 1, "red", ifelse(value == 2, "blue", "green")))

#e_min <- extent(99.8, 101.2, 12.9, 13.7)

ndvi <- raster("./data/processed/centro_ndvi.tif") %>%
  crop(e)

ndvi_df <- as.data.frame(ndvi, na.rm = T, xy = T) 
ndvi_df <- ndvi_df %>%
  rename(value = "2", x = "x", y = "centro_ndvi")

ndvi_60 <- aggregate(ndvi, fact = 2)
ndvi_60_df <- as.data.frame(ndvi_90, na.rm = T, xy = T) %>%
  rename(y = "y", x = "x", value = "centro_ndvi")

# ndvi_120 <- aggregate(ndvi, fact = 4)
# ndvi_120_df <- as.data.frame(ndvi_150, na.rm = T, xy = T) %>%
#   rename(y = "y", x = "x", value = "centro_ndvi")

ndvi_inset <- ndvi %>%
  crop(extent(99.8, 100.1, 13.15, 13.45))

ndvi_inset_df <- as.data.frame(ndvi_inset, na.rm = T, xy = T) %>%
  rename(y = "y", x = "x", value = "centro_ndvi")

luc_plot <- ggplot() +
  geom_raster(data = ndvi_60_df, aes(x = x, y = y, alpha = value, colour = value)) +
  geom_raster(data = luc_df, aes(x = x, y = y, fill = factor(value))) +
  geom_rect(aes(xmin = 99.85, xmax = 100.05, ymin = 13.2, ymax = 13.4), color = "red", fill = "NA") +
  scale_fill_manual(values = c("red", "green", "dark green")) +
  theme_bw() +
  coord_sf(xlim = c(99.8, 101.2), ylim = c(12.9, 13.7)) +
  scale_y_continuous(breaks = seq(12.9, 13.7, 0.2)) +
  scale_x_continuous(breaks = seq(99, 102, 0.5)) +
  theme(axis.title.x = element_blank(),
        axis.title.y = element_blank(),
        legend.position = "none")
      
print(luc_plot)

luc_inset <- ggplot() +
  geom_raster(data = ndvi_inset_df, aes(x = x, y = y, alpha = value, colour = "white")) +
  geom_raster(data = luc_df, aes(x = x, y = y, fill = factor(value))) +
  scale_fill_manual(values = c("red", "green", "dark green")) +
  theme_bw() +
  coord_sf(xlim = c(99.85, 100.05), ylim = c(13.2, 13.4)) +
  scale_y_continuous(breaks = seq(13.2, 13.4, 0.1)) +
  scale_x_continuous(breaks = seq(99.85, 100.05, 0.1)) +
  theme(axis.title.x = element_blank(),
        axis.title.y = element_blank(),
        legend.position = "none")
  
#luc_inset

luc_grob <- ggplotGrob(luc_plot)
inset_grob <- ggplotGrob(luc_inset)

panel <- gridExtra::arrangeGrob(inset_grob, luc_grob, nrow = 1, ncol = 2, widths = c(0.4, 0.67))

plot(panel)
  
ggplot2::ggsave(luc_plot, device = "jpeg", 
                filename = "./figs/draft_luc_plot_2.jpg", 
                width = 10, height = 9, units = "in")


ggplot2::ggsave(panel, device = "jpeg", 
                filename = "./figs/draft_luc_plot_w_inset.jpg", 
                width = 9, height = 5, units = "in")


  

#-----------------------------
# Next step for spatial analyses - what is it?
# Chongwat's coding
# 1: Central
# 2: Eastern
# 3: Eastern Peninsula
# 4: Western Peninsula

library(raster)
library(rgdal)
library(sf)
library(tidyverse)
  
loss <- raster("./data/processed/loss.tif")
gain <- raster("./data/processed/gain.tif")
same <- raster("./data/processed/noChange.tif")

chongwats <- raster("~/Dropbox/manuscripts/ch2_luc/analysis/data/scratch/chongwats.tif")

loss_nums <- zonal(loss, chongwats, fun="sum", na.rm=TRUE)
gain_nums <- zonal(gain, chongwats, fun="sum", na.rm=TRUE)
same_nums <- zonal(same, chongwats, fun="sum", na.rm=TRUE)

zonal(thai1996, chongwats, fun = "sum", na.rm = TRUE)

#---------------------------------------------------------------
# Carbon summary

library(tidyverse)
library(raster)
library(sp)

chongwats <- raster("~/Dropbox/manuscripts/ch2_luc/analysis/data/scratch/chongwats.tif")
agb <- raster("./data/raw/carbon/Mangrove_agb_Thailand.tif")
soc <- raster("./data/raw/carbon/Mangrove_soc_Thailand.tif")

cw_agb <- resample(chongwats, agb, "bilinear")
cw_agb <- crop(cw_agb, extent(agb))
    
cw_soc <- resample(chongwats, soc, "bilinear")
cw_soc <- crop(cw_soc, extent(soc))

agb_mean <- zonal(agb, cw_agb, fun="mean", na.rm=TRUE)
agb_sd <- zonal(agb, cw_agb, fun="sd", na.rm=TRUE)

soc_mean <- zonal(soc, cw_soc, fun="mean", na.rm=TRUE)
soc_sd <- zonal(soc, cw_soc, fun="sd", na.rm=TRUE)

#--------------------------------------
# Processing DMCR Thai LULC dataset.
# Outputs pts files with land cover attached, which is fed into GEE script for
# supervised classification of land use in Thailand. Validated with 2014 coastal
# land use dataset.

library(tidyverse)
library(sf)
library(sp)
library(raster)
library(rgdal)

# Load in datasets  

lulc2000 <- read_sf("~/Documents/dmcr_data/Land use (2000 and 2014)/MG_TYPE_43.shp") %>%
  dplyr::select(code = CODE) %>%
  mutate(code = ifelse(code %in% c("Mi"), "Unk", code))
  
lulc2014 <- read_sf("~/Documents/dmcr_data/Land use (2000 and 2014)/MG_TYPE_57_bffr.shp") %>%
  dplyr::select(code = CODE) %>%
  mutate(code = ifelse(code %in% c("S", "W"), "Unk", code))

thai <- read_sf("~/Dropbox/manuscripts/ch2_luc/analysis/data/raw/tha_admbnda_adm0_rtsd_20190221.shp") %>%
  st_transform(st_crs(lulc2000))

# Processing pts data

pts2000 <- st_sample(lulc2000, 2500, type = "random", exact = TRUE)
pts2014 <- st_sample(lulc2014, 2500, type = "random", exact = TRUE)

ptsData2000 <- st_intersection(lulc2000, pts2000) %>%
  st_intersection(thai) %>%
  mutate(code_num = as.numeric(as.factor(code))) %>%
  dplyr::select(code, code_num)

pts2000_df <- ptsData2000
st_geometry(pts2000_df) <- NULL

ptsData2014 <- st_intersection(lulc2014, pts2014) %>%
  st_intersection(thai) %>%
  mutate(code_num = as.numeric(as.factor(code))) %>%
  dplyr::select(code, code_num)

pts2014_df <- ptsData2014
st_geometry(pts2014_df) <- NULL

pts2000_df %>%
  unique() %>%
  arrange(code_num)

pts2014_df %>%
  unique() %>%
  arrange(code_num)
  
# Write out shapefiles

st_write(ptsData2000, "~/Documents/dmcr_data/pts2000", layer = "ptsData_2000", driver = "ESRI Shapefile")
st_write(ptsData2014, "~/Documents/dmcr_data/pts2014", layer = "ptsData_2014", driver = "ESRI Shapefile")

library(randomForest)

newDat <- read_sf("~/Documents/dmcr_data/drive-download-20200226T232913Z-001/exported2014points.shp")

newDat <- newDat %>%
  rename(orig = code_num,
         pred = first)

st_geometry(newDat) <- NULL

dat <- drop_na(newDat) %>%
  mutate(code_num = as.factor(code),
         idx = row_number()) %>%
  filter(!(code_num %in% c(3, 4, 8))) %>%
  dplyr::select(code_num, ndmi, mmri, mndwi, evi, diff, ndvi, ndwi, dtm, ndsi, idx)

trnDat <- sample_n(dat, 1500) 

valDat <- dat %>%
  filter(!(idx %in% trnDat$idx))

trnDat <- dplyr::select(trnDat, -idx)
valDat <- dplyr::select(valDat, -idx)

rf <- randomForest(code_num ~ ., data = trnDat)

pred <- predict(rf, valDat)

cm <- table(newDat$orig, newDat$pred)

#------------------------------------------------------
# Analysis of zonal areas
# Analysis of difference in land cover type

library(raster)
library(rgdal)
library(sf)
library(sp)
library(tidyverse)

lulc2000 <- raster("~/Documents/dmcr_data/Land use (2000 and 2014)/lulc2000.tif")
lulc2014 <- raster("~/Documents/dmcr_data/Land use (2000 and 2014)/lulc2014.tif")

lulcc <- crosstab(lulc2000, lulc2014, useNA=FALSE)

lulcc_df <- as.data.frame.matrix(round(lulcc * 900 / 10000 / 1000, 2))

lulcc_df$sum <- rowSums(lulcc_df)
  lulcc_df[13, ] <- colSums(lulcc_df)


write_csv(lulcc, "~/Desktop/lulcc.csv")

lulcc_rast <- lulc2000 + lulc2014*100

writeRaster(lulcc_rast, "~/Documents/dmcr_data/Land use (2000 and 2014)/lulcc.tif", format = "GTiff", options="COMPRESS=DEFLATE")

sf_dat <- read_sf("~/Documents/dmcr_data/Land use (2000 and 2014)/MG_TYPE_43.shp") %>%
  mutate(CODE = ifelse(CODE == "Mi", "Unk", CODE)) %>%
  arrange(CODE) %>%
  mutate(CODE_NUM = 1:length(CODE)) %>%
  dplyr::select(CODE, CODE_NUM)
