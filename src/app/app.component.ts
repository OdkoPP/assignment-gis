import { Component } from '@angular/core';

@Component({
  selector: 'app-root',
  templateUrl: './app.component.html',
  styleUrls: ['./app.component.less']
})
export class AppComponent {

  public selectedPosition: [number, number];
  public routeAnalysis: any;

  public activeStartingPoints: any = {
    parking: true,
    bus: true,
    train: true
  };
  public startingPointActiveChange(): void {
    this.activeStartingPoints = JSON.parse(JSON.stringify(this.activeStartingPoints));
  }

  public defaultCounter: number = 0;
  public resetDefault(): void {
    this.defaultCounter++;
    this.activeStartingPoints.parking = true;
    this.activeStartingPoints.bus = true;
    this.activeStartingPoints.train = true;

    this.selectedPosition = undefined;
    this.routeAnalysis = undefined;
  }

  public selectedPositionChanged(selectedPosition: [number, number]) {
    this.selectedPosition = selectedPosition;
  }

  public routeAnalysisChanged(routeAnalysis: any) {
    this.routeAnalysis = routeAnalysis;
    this.routeAnalysis.features = this.routeAnalysis.features.filter( e => e.properties.distance !== 0);
    console.log(routeAnalysis);
  }

}
