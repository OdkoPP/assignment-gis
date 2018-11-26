import { Injectable } from '@angular/core';
import { HttpClient, HttpHeaders } from '@angular/common/http';
import { Observable } from 'rxjs';
import * as mapboxgl from 'mapbox-gl';
import { environment } from '../../environments/environment';

@Injectable()
export class DataService {

    private API_URL = '/api/v1';

    private httpOptions = { headers: new HttpHeaders({'Content-Type':  'application/json'}) };

    constructor(
        private _httpClient: HttpClient
    ) {
        mapboxgl.accessToken = environment.mapbox.accessToken;
    }

    public getTrails(): Observable<any> {
        return this._httpClient
            .get<any[]>(this.API_URL + '/trails', this.httpOptions);
    }

    public getDominantPeaks(): Observable<any> {
        return this._httpClient
            .get<any[]>(this.API_URL + '/dominant_peaks', this.httpOptions);
    }

    public getStartingPoints(activeStartingPoints: string[]): Observable<any> {
        return this._httpClient
            .get<any[]>(this.API_URL + '/starting_points?' + this.activeStartingPointsToUrlArray(activeStartingPoints), this.httpOptions);
    }

    public getRouteToNearestStartingPoint(lon: number, lat: number, activeStartingPoints: string[]): Observable<any> {
        return this._httpClient
            .get<any[]>(this.API_URL + '/route_to_nearest_starting_point/' + lon + '/' + lat + '?' + this.activeStartingPointsToUrlArray(activeStartingPoints), this.httpOptions);
    }

    public getRouteAnalysis(lon: number, lat: number, activeStartingPoints: string[]): Observable<any> {
        return this._httpClient
            .get<any[]>(this.API_URL + '/route_analysis/' + lon + '/' + lat + '?' + this.activeStartingPointsToUrlArray(activeStartingPoints), this.httpOptions);
    }

    private activeStartingPointsToUrlArray(activeStartingPoints: string[]): string {
        return activeStartingPoints.map( e => 'activeStartingPoints[]=' + e).join('&');
    }

}
