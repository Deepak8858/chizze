package main

import (
	"fmt"
	"io"
	"net/http"
	"sync"
	"sync/atomic"
	"time"
)

func main() {
	url := "http://localhost:8080/health"
	totalRequests := 50000
	concurrency := 500

	client := &http.Client{
		Timeout: 5 * time.Second,
		Transport: &http.Transport{
			MaxIdleConns:        600,
			MaxIdleConnsPerHost: 600,
			MaxConnsPerHost:     600,
			IdleConnTimeout:     90 * time.Second,
		},
	}

	var success, failed int64
	var wg sync.WaitGroup
	sem := make(chan struct{}, concurrency)

	start := time.Now()

	for i := 0; i < totalRequests; i++ {
		wg.Add(1)
		sem <- struct{}{}
		go func() {
			defer wg.Done()
			defer func() { <-sem }()

			resp, err := client.Get(url)
			if err != nil {
				atomic.AddInt64(&failed, 1)
				return
			}
			io.Copy(io.Discard, resp.Body)
			resp.Body.Close()

			if resp.StatusCode == 200 {
				atomic.AddInt64(&success, 1)
			} else {
				atomic.AddInt64(&failed, 1)
			}
		}()
	}

	wg.Wait()
	elapsed := time.Since(start)

	rps := float64(totalRequests) / elapsed.Seconds()
	fmt.Println("═══════════════════════════════════════")
	fmt.Println("  Load Test Results")
	fmt.Println("═══════════════════════════════════════")
	fmt.Printf("  Total:       %d requests\n", totalRequests)
	fmt.Printf("  Concurrency: %d\n", concurrency)
	fmt.Printf("  Success:     %d\n", success)
	fmt.Printf("  Failed:      %d\n", failed)
	fmt.Printf("  Duration:    %v\n", elapsed.Round(time.Millisecond))
	fmt.Printf("  RPS:         %.0f req/s\n", rps)
	fmt.Printf("  Avg Latency: %.2f ms\n", elapsed.Seconds()/float64(totalRequests)*1000*float64(concurrency))
	fmt.Println("═══════════════════════════════════════")
}
