import { Component, OnInit, Input, Output, EventEmitter } from '@angular/core';
import * as mapboxgl from 'mapbox-gl';
import { DataService } from './data.service';
import { GeoJson, FeatureCollection } from './map';


@Component({
  selector: 'app-map-box',
  templateUrl: './map-box.component.html',
  styleUrls: ['./map-box.component.less']
})
export class MapBoxComponent implements OnInit {

  @Input('defaultCounter')
  set defaultCounter(value: number) {
    this.resetDefault();
    this.selectedPosition = undefined;
  }

  @Input('activeStartingPointsInput')
  set activeStartingPointsInput(value: any) {
    this.activeStartingPoints = value;

    if (this.map !== undefined) {
      this.loadStartingPoints();
      if (this.selectedPosition !== undefined) {
        this.loadRouteToNearestStartingPoint();
      }
    }
  }
  private activeStartingPoints: any;

  @Output() selectedPositionEmitter = new EventEmitter<[number, number]>();
  @Output() routeAnalysisEmitter = new EventEmitter<any>();

  public selectedPosition: [number, number];

  // Default settings
  private map: mapboxgl.Map;
  private style = 'mapbox://styles/mapbox/streets-v10';
  private lat = 49.2;
  private lng = 19.975;
  private zoom = 10;
  private startingPointsMarkers: any[] = [];
  private dominantPeaksMarkers: any[] = [];

  private startingPointTypeToIconMapping: any = {
    parking: {
      color: 'blue',
      icon: 'fa-car'
    },
    bus: {
      color: 'red',
      icon: 'fa-bus'
    },
    train: {
      color: 'orange',
      icon: 'fa-train'
    }
  };

  constructor(
    private _dataService: DataService
  ) {}

  ngOnInit() {
    this.initializeMap();
  }

  private initializeMap() {
    const that = this;

    // Initialize map
    this.map = new mapboxgl.Map({
      container: 'map',
      style: this.style,
      zoom: this.zoom,
      center: [this.lng, this.lat]
    });

    // Load default layers
    this.map.on('load', () => {
      this.loadTrails();
      this.loadStartingPoints();
      this.loadDominantPeaks();
    });

    this.map.on('zoom', () => {
      if (this.map.getZoom() > 11.5) {
        this.dominantPeaksMarkers.forEach( e => e.addTo(this.map));
      } else {
        this.dominantPeaksMarkers.forEach( e => e.remove());
      }
    });

    // Find nearest route and route to nearest starting point on click
    this.map.on('click', e => {
      this.selectedPosition = [e.lngLat.lng, e.lngLat.lat];
      this.selectedPositionEmitter.emit(this.selectedPosition);

      that.loadRouteToNearestStartingPoint();
      that.loadRouteAnalysis();
    });

    // Add map controls (zoom, compas, ...)
    this.map.addControl(new mapboxgl.NavigationControl());
  }

  private resetDefault(): void {
    if (this.map !== undefined) {
      this.map.setZoom(this.zoom);
      this.map.setCenter([this.lng, this.lat]);

      this.loadTrails();
      this.loadStartingPoints();
    }
  }

  private loadDominantPeaks() {
    this._dataService.getDominantPeaks().subscribe(
      data => {
        if (this.map.getSource('DominantPeaks') !== undefined) {
          this.map.removeSource('DominantPeaks');
        }

        this.dominantPeaksMarkers.forEach(e => e.remove());

        this.map.addSource('DominantPeaks', {
          type: 'geojson',
          data: data
        });

        data.features.forEach( m => {
          const elContainer = document.createElement('div');
          elContainer.style.width = '10000px';
          elContainer.style.textAlign = 'center';
          elContainer.style.lineHeight = '10px';
          elContainer.innerHTML = `
            <i class='marker fa fa-dot-circle-o'></i>
            <br>
            <span>${m.properties.name}</span>
            <br>
            <span>${m.properties.ele}</span>
          `;

          // Add marker to map and save it
          this.dominantPeaksMarkers.push(new mapboxgl.Marker(elContainer)
            .setLngLat(m.geometry.coordinates)
          );

        });
      },
      err => console.log(err)
    );
  }

  private loadTrails() {
    this._dataService.getTrails().subscribe(
      data => {
        if (this.map.getSource('Trails') !== undefined) {
          if (this.map.getLayer('Trails') !== undefined) {
            this.map.removeLayer('Trails');
          }
          this.map.removeSource('Trails');
        }

        if (this.map.getSource('NearestStartingPoint') !== undefined) {
          if (this.map.getLayer('NearestStartingPoint') !== undefined) {
            this.map.removeLayer('NearestStartingPoint');
          }
          this.map.removeSource('NearestStartingPoint');
        }

        this.map.addSource( 'Trails', {
          type: 'geojson',
          data: data
        });

        this.map.addLayer({
          id: 'Trails',
          type: 'line',
          source: 'Trails',
          paint: {
            'line-color': ['get', 'color'],
            'line-width': ['case', ['boolean', ['feature-state', 'hover'], false], 10, 3]
          }
        });

        let hoveredStateId =  null;

        this.map.on('mousemove', 'Trails', function(e) {
          if (hoveredStateId) {
            this.setFeatureState({source: 'Trails', id: hoveredStateId}, { hover: false});
          }

          hoveredStateId = e.features[0].id;
          this.setFeatureState({source: 'Trails', id: hoveredStateId}, { hover: true});
        });

        this.map.on('mouseleave', 'Trails', function() {
          if (hoveredStateId) {
            this.setFeatureState({source: 'Trails', id: hoveredStateId}, { hover: false});
          }
          hoveredStateId =  null;
        });
      },
      err => console.log(err)
    );
  }

  private getActiveStartingPointsAsArray(): string[] {
    return Object.keys(this.activeStartingPoints).filter( e => this.activeStartingPoints[e] === true);
  }

  private loadStartingPoints() {
    this._dataService.getStartingPoints(this.getActiveStartingPointsAsArray()).subscribe(
      data => {

        if (this.map.getSource('StartingPoints') !== undefined) {
          this.map.removeSource('StartingPoints');
        }

        this.startingPointsMarkers.forEach(e => e.remove());

        this.map.addSource('StartingPoints', {
          type: 'geojson',
          data: data
        });

        data.features.forEach( m => {
          const iconToUse = this.startingPointTypeToIconMapping[m.properties.type];

          const el = document.createElement('div');
          el.className = 'marker fa ' + iconToUse.icon;
          el.style.width = '15px';
          el.style.height = '15px';
          el.style.borderRadius = '3px';
          el.style.backgroundColor = 'white';
          el.style.textAlign = 'center';
          el.style.paddingTop = '2px';
          el.style.color = iconToUse.color;

          // Add marker to map and save it
          this.startingPointsMarkers.push(new mapboxgl.Marker(el)
            .setLngLat(m.geometry.coordinates)
            .addTo(this.map)
          );

        });
      },
      err => console.log(err)
    );
  }

   // Find nearest trail and route to nearest starting point on click
   private loadRouteToNearestStartingPoint() {
    this._dataService.getRouteToNearestStartingPoint(this.selectedPosition[0], this.selectedPosition[1], this.getActiveStartingPointsAsArray()).subscribe(
      data => {
        // Trails color amount reduce
        const allRouteColorsCount = [].concat(...data.features.map(d => d.properties).map(e => e.color).filter(e => e !== null).map( e => e.replace('{', '').replace('}', '').split(',')))
                                  .reduce((prev, curr) => (prev[curr] = ++prev[curr] || 1, prev), {});
        const orderedRouteColor = Object.keys(allRouteColorsCount).sort( (a, b) => allRouteColorsCount[b] - allRouteColorsCount[a]);

        data.features.map(d => d.properties).forEach(e => {
          if (e.color !== null) {
            e.color = e.color.replace('{', '').replace('}', '').split(',');
            for (const c of orderedRouteColor) {
              if (e.color.includes(c)) {
                e.color = c;
                break;
              }
            }
          }
        });

        if (this.map.getSource('Trails') !== undefined) {
          if (this.map.getLayer('Trails') !== undefined) {
            this.map.setPaintProperty('Trails', 'line-opacity', 0.3);
          }
        }

        if (this.map.getSource('NearestStartingPoint') !== undefined) {
          if (this.map.getLayer('NearestStartingPoint') !== undefined) {
            this.map.removeLayer('NearestStartingPoint');
          }
          this.map.removeSource('NearestStartingPoint');
        }

        this.map.addSource('NearestStartingPoint', {
          type: 'geojson',
          data: data
        });

        this.map.addLayer({
          id: 'NearestStartingPoint',
          type: 'line',
          source: 'NearestStartingPoint',
          paint: {
            'line-color': ['get', 'color'],
            'line-width': 10
          }
        });
      },
      err => console.log(err)
    );
  }

  private loadRouteAnalysis() {
    this._dataService.getRouteAnalysis(this.selectedPosition[0], this.selectedPosition[1], this.getActiveStartingPointsAsArray()).subscribe(
      data => this.routeAnalysisEmitter.emit(data),
      err => console.log(err)
    );
  }

}
